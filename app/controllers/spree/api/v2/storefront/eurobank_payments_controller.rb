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
                            
                            preferences = payment.payment_method.preferences
                            raise 'There is no preferences on payment methods' unless preferences

                            uuid = SecureRandom.uuid

                            string = [
                                2, # version
                                preferences[:merchant_id], # mid
                                'el', # lang
                                payment.order.number, # orderid
                                'Ηλεκτρονική Παραγγελία', # orderDesc
                                payment.amount, # orderAmount
                                'EUR', # currency
                                preferences[:confirm_url], # confirmUrl
                                preferences[:cancel_url], # cancelUrl
                                uuid, # var1
                                'Cardlink1', # shared secret
                            ].join

                            digest = Base64.encode64(Digest::SHA256.digest string).strip
                           
                            payment.eurobank_payments.create!(
                                digest: digest,
                                uuid: uuid
                            )
                            
                            render json: {digest: digest, uuid: uuid}
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
                    def eurobank_payment_params
                        params.require(:eurobank_payment).permit!
                    end
                end
            end
        end
    end
end