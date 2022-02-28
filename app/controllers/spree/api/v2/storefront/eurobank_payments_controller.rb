module Spree
    module Api
        module V2
            module Storefront
                class EurobankPaymentsController < ::Spree::Api::V2::BaseController
                    include Spree::Api::V2::Storefront::OrderConcern
                    before_action :ensure_order, only: :create
                    
                    def create
                        spree_authorize! :update, spree_current_order, order_token

                        payment = spree_current_order.payments.valid.find{|p| p.state != 'void'}
        
                        begin
                            raise 'There is no active payment method' unless payment

                            unless payment.payment_method.type === "Spree::PaymentMethod::EurobankPayment"
                                raise 'Order has not EurobankPayment'
                            end
                            
                            url = 'https://paycenter.piraeusbank.gr/services/tickets/issuer.asmx'

                            preferences = payment.payment_method.preferences
                            raise 'There is no preferences on payment methods' unless preferences

                            password = Digest::MD5.hexdigest(preferences[:password])

                            uuid = SecureRandom.uuid

                            message = %Q[<?xml version="1.0" encoding="utf-8"?>
                                <soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
                                <soap12:Body>
                                    <IssueNewTicket xmlns="http://piraeusbank.gr/paycenter/redirection">
                                    <Request>
                                        <Username>#{preferences[:user_name]}</Username>
                                        <Password>#{password}</Password>
                                        <MerchantId>#{preferences[:merchant_id]}</MerchantId>
                                        <PosId>#{preferences[:pos_id]}</PosId>
                                        <AcquirerId>#{preferences[:acquirer_id]}</AcquirerId>
                                        <MerchantReference>#{payment.number}</MerchantReference>
                                        <RequestType>02</RequestType>
                                        <ExpirePreauth>0</ExpirePreauth>
                                        <Amount>#{payment.amount}</Amount>
                                        <CurrencyCode>978</CurrencyCode>
                                        <Installments>0</Installments>
                                        <Bnpl>0</Bnpl>
                                        <Parameters>#{uuid}</Parameters>
                                    </Request>
                                    </IssueNewTicket>
                                </soap12:Body>
                                </soap12:Envelope>]

                            response = Net::HTTP.post(
                                URI(url),
                                message.strip,
                                'Content-Type' => 'application/soap+xml; charset=UTF-8'
                            )

                            body = response.body

                            result_code = body.match(/<ResultCode>(\d)<\/ResultCode>/)
                            result_description = body.match(/<ResultDescription>(.*)<\/ResultDescription>/)
                            result_tran_ticket = body.match(/<TranTicket>(\S+)<\/TranTicket>/)
                            result_timestamp = body.match(/<Timestamp>(\S+)<\/Timestamp>/)
                            
                            if result_code && result_code[1].to_i == 0
                                payment.eurobank_payments.create!(
                                    transaction_ticket: result_tran_ticket[1],
                                    uuid: uuid
                                )
                                
                                render json: {code: result_code[1].to_i}
                            else
                                render_error_payload(result_description[1])
                            end
                        rescue => exception
                            render_error_payload(exception.to_s)
                        end
                    end

                    def failure
                        fields = params.require(:eurobank_payment).permit!

                        eurobank_payment = Spree::EurobankPayment.find_by(uuid: fields[:parameters])
                        
                        eurobank_payment.payment.update(response_code: fields[:support_reference_id])
                        eurobank_payment.payment.failure

                        if eurobank_payment.update(eurobank_payment_params('failure'))
                            render json: {ok: true}
                        else
                            render json: {ok: false, errors: eurobank_payment.errors.full_messages}, status: 400
                        end
                    end

                    def success
                        fields = params.require(:eurobank_payment).permit!

                        eurobank_payment = Spree::EurobankPayment.find_by(uuid: fields[:parameters])
                        payment = eurobank_payment.payment
                        preferences = payment.payment_method.preferences

                        hash_key = [
                            eurobank_payment.transaction_ticket,
                            preferences[:pos_id],
                            preferences[:acquirer_id],
                            payment.number,
                            fields[:approval_code],
                            fields[:parameters],
                            fields[:response_code],
                            fields[:support_reference_id],
                            fields[:auth_status],
                            fields[:package_no],
                            fields[:status_flag],
                        ].join(';')

                        secure_hash = OpenSSL::HMAC.hexdigest('SHA256', eurobank_payment.transaction_ticket, hash_key)

                        if eurobank_payment.update(eurobank_payment_params('success'))
                            payment.update(response_code: fields[:support_reference_id])

                            if secure_hash.upcase === fields[:hash_key]
                                payment.complete

                                render json: {ok: true}
                            else
                                payment.void
    
                                render json: {ok: false, error: "Hash Key is not correct"}, status: 400
                            end
                        else
                            payment.failure
                            
                            render json: {ok: false, errors: eurobank_payment.errors.full_messages}, status: 400
                        end
                    end

                    private
                    def eurobank_payment_params(state)
                        if state == 'success'
                            params.require(:eurobank_payment)
                                .permit(:support_reference_id , :merchant_reference, :status_flag, :response_code, 
                                    :response_description, :approval_code, :package_no, :auth_status, :transaction_id)
                        else
                            params.require(:eurobank_payment)
                                .permit(:support_reference_id , :merchant_reference, 
                                    :result_code, :result_description, :response_code, :response_description)
                        end
                    end
                end
            end
        end
    end
end