module Spree
    module Api
        module V2
            module Storefront
                class CardlinkPaymentsController < ::Spree::Api::V2::BaseController
                    include Spree::Api::V2::Storefront::OrderConcern
                    before_action :ensure_order, only: :create
                    
                    def create
                        spree_authorize! :update, spree_current_order, order_token

                        payment = spree_current_order.payments.valid.find{|p| p.state != 'void'}
        
                        begin
                            raise 'There is no active payment method' unless payment

                            unless payment.payment_method.type === "Spree::PaymentMethod::CardlinkPayment"
                                raise 'Order has not CardlinkPayment'
                            end
                            
                            preferences = payment.payment_method.preferences
                            raise 'There is no preferences on payment methods' unless preferences

                            bill_address = payment.order.bill_address

                            token = SecureRandom.base58(24)

                            string = [
                                2, # version
                                preferences[:merchant_id], # mid
                                params[:lang], # lang
                                token, # orderid
                                'Ηλεκτρονική Παραγγελία', # orderDesc
                                payment.amount, # orderAmount
                                'EUR', # currency
                                bill_address.country.iso, # billCountry
                                bill_address.zipcode, # billZip
                                bill_address.city, # billCity
                                bill_address.address1, # billAddress
                                preferences[:confirm_url], # confirmUrl
                                preferences[:cancel_url], # cancelUrl
                                preferences[:shared_secret], # shared secret
                            ].join.strip

                            digest = Base64.encode64(Digest::SHA256.digest string).strip

                            cardlink_payment = payment.cardlink_payments.create!(digest: digest, token: token)
                            
                            render json: {digest: digest, token: token}
                        rescue => exception
                            render_error_payload(exception.to_s)
                        end
                    end

                    def failure
                        fields = params.require(:cardlink_payment).permit!

                        cardlink_payment = Spree::CardlinkPayment.find_by(token: fields[:token])
                        
                        cardlink_payment.payment.update(response_code: fields[:tx_id])
                        cardlink_payment.payment.failure

                        if cardlink_payment.update(cardlink_payment_params)
                            render json: {ok: true}
                        else
                            render json: {ok: false, errors: cardlink_payment.errors.full_messages}, status: 400
                        end
                    end

                    def success
                        fields = params.require(:cardlink_payment).permit!

                        cardlink_payment = Spree::CardlinkPayment.find_by(token: fields[:token])
                        payment = cardlink_payment.payment

                        if cardlink_payment.update(cardlink_payment_params)
                            payment.update(response_code: fields[:tx_id])

                            preferences = payment.payment_method.preferences
                            raise 'There is no preferences on payment methods' unless preferences

                            bill_address = payment.order.bill_address

                            string = [
                                2, # version
                                preferences[:merchant_id], # mid
                                fields[:token], # orderid
                                fields[:status],
                                payment.amount, # orderAmount
                                'EUR', # currency
                                fields[:paymentTotal],
                                fields[:message],
                                fields[:riskScore],
                                fields[:payMethod],
                                fields[:tx_id],
                                fields[:payment_ref],
                                preferences[:shared_secret], # shared secret
                            ].join.strip

                            digest = Base64.encode64(Digest::SHA256.digest string).strip

                            if digest === fields[:digest]
                                payment.complete
                                complete_service.call(order: payment.order)

                                render json: {ok: true}
                            else
                                payment.void
    
                                render json: {ok: false, error: "Digest is not correct"}, status: 400
                            end
                        else
                            payment.failure
                            
                            render json: {ok: false, errors: cardlink_payment.errors.full_messages}, status: 400
                        end
                    end

                    private
                    def cardlink_payment_params
                        params.require(:cardlink_payment).permit(:status, :message, :tx_id, :payment_ref, :digest)
                    end

                    def complete_service
                        Spree::Api::Dependencies.storefront_checkout_complete_service.constantize
                    end
                end
            end
        end
    end
end