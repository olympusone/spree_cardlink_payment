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

                            bill_address = payment.order.bill_address

                            puts request.host

                            string = [
                                2, # version
                                preferences[:merchant_id], # mid
                                'el', # lang
                                payment.number, # orderid
                                'Ηλεκτρονική Παραγγελία', # orderDesc
                                payment.amount, # orderAmount
                                'EUR', # currency
                                bill_address.country.iso, # billCountry
                                bill_address.zipcode, # billZip
                                bill_address.city, # billCity
                                bill_address.address1, # billAddress
                                preferences[:confirm_url], # confirmUrl
                                preferences[:cancel_url], # cancelUrl
                                uuid,
                                preferences[:shared_secret], # shared secret
                            ].join.strip

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

                        eurobank_payment = Spree::EurobankPayment.find_by(uuid: fields[:uuid])
                        
                        eurobank_payment.payment.update(response_code: fields[:tx_id])
                        eurobank_payment.payment.failure

                        if eurobank_payment.update(eurobank_payment_params)
                            render json: {ok: true}
                        else
                            render json: {ok: false, errors: eurobank_payment.errors.full_messages}, status: 400
                        end
                    end

                    def success
                        fields = params.require(:eurobank_payment).permit!

                        eurobank_payment = Spree::EurobankPayment.find_by(uuid: fields[:uuid])

                        if eurobank_payment.update(eurobank_payment_params)
                            payment.update(response_code: fields[:tx_id])

                            if eurobank_payment.digest === fields[:digest]
                                payment.complete

                                render json: {ok: true}
                            else
                                payment.void
    
                                render json: {ok: false, error: "Digest is not correct"}, status: 400
                            end
                        else
                            payment.failure
                            
                            render json: {ok: false, errors: eurobank_payment.errors.full_messages}, status: 400
                        end
                    end

                    private
                    def eurobank_payment_params
                        params.require(:eurobank_payment).permit(:status, :message, :tx_id, :payment_ref)
                    end
                end
            end
        end
    end
end