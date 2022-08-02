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

                            confirm_url = URI.join(preferences[:host], "/api/v2/storefront/cardlink_payments/success")
                            cancel_url = URI.join(preferences[:host], "/api/v2/storefront/cardlink_payments/failure")

                            orderid = SecureRandom.base58(24)

                            currency = Spree::Store.current.default_currency
                            locale = Spree::Store.current.default_locale

                            string = [
                                2, # version
                                preferences[:merchant_id], # mid
                                params[:locale] || locale, # lang
                                orderid, # orderid
                                spree_current_order.number, # orderDesc
                                payment.amount, # orderAmount
                                currency, # currency
                                bill_address.country.iso, # billCountry
                                bill_address.zipcode, # billZip
                                bill_address.city, # billCity
                                bill_address.address1, # billAddress
                                confirm_url, # confirmUrl
                                cancel_url, # cancelUrl
                                preferences[:shared_secret], # shared secret
                            ].join.strip

                            digest = Base64.encode64(Digest::SHA256.digest string).strip

                            cardlink_payment = payment.cardlink_payments.create!(
                                digest: digest, 
                                orderid: orderid
                            )
                            
                            render json: {string: string, digest: digest, orderid: orderid, confirm_url: confirm_url, cancel_url: cancel_url}
                        rescue => exception
                            render_error_payload(exception.to_s)
                        end
                    end

                    def failure
                        begin
                            cardlink_payment = Spree::CardlinkPayment.find_by(orderid: params[:orderid], tx_id: nil)                            
                            raise 'Payment not found' unless cardlink_payment

                            payment = cardlink_payment.payment

                            preferences = payment.payment_method.preferences
                            raise 'There is no preferences on payment methods' unless preferences

                            raise 'Payment not found' unless params[:mid] == preferences[:merchant_id]

                            string = [
                                params[:version],
                                preferences[:merchant_id],
                                params[:orderid],
                                params[:status],
                                params[:orderAmount],
                                params[:currency],
                                params[:paymentTotal],
                                params[:message],
                                params[:riskScore],
                                params[:txId],
                                preferences[:shared_secret]
                            ].join.strip

                            digest_result = Base64.encode64(Digest::SHA256.digest string).strip

                            raise "Wrong data is given!" unless digest_result == params[:digest]
                            
                            cardlink_payment.payment.update(response_code: params[:tx_id])
                            cardlink_payment.payment.failure

                            cardlink_payment.update(tx_id: params[:txId], status: params[:status], message: params[:message])

                            redirect_to URI::join(
                                preferences[:cancel_url], 
                                "?txId=#{params[:txId]}&status=#{params[:status]}&message=#{params[:message]}").to_s
                        rescue => exception
                            render_error_payload(exception.to_s)
                        end
                    end

                    def success
                        begin
                            cardlink_payment = Spree::CardlinkPayment.find_by(orderid: params[:orderid], tx_id: nil)                            
                            raise 'Payment not found' unless cardlink_payment

                            payment = cardlink_payment.payment

                            preferences = payment.payment_method.preferences
                            raise 'There is no preferences on payment methods' unless preferences

                            raise 'Payment not found' unless params[:mid] == preferences[:merchant_id]

                            string = [
                                params[:version],
                                preferences[:merchant_id],
                                params[:orderid],
                                params[:status],
                                params[:orderAmount],
                                params[:currency],
                                params[:paymentTotal],
                                params[:message],
                                params[:riskScore],
                                params[:payMethod],
                                params[:txId],
                                params[:paymentRef],
                                preferences[:shared_secret]
                            ].join.strip

                            digest_result = Base64.encode64(Digest::SHA256.digest string).strip

                            raise "Wrong data is given!" unless digest_result == params[:digest]

                            cardlink_payment.update(
                                status: params[:status],
                                message: params[:message],
                                tx_id: params[:txId],
                                payment_ref: params[:paymentRef]
                            )

                            payment.update(response_code: params[:tx_id])

                            if ['AUTHORIZED', 'CAPTURED'].include?(params[:status])
                                payment.complete
                                complete_service.call(order: payment.order)

                                redirect_url = preferences[:confirm_url]
                            else
                                payment.failure

                                redirect_url = preferences[:cancel_url]
                            end

                            redirect_to URI::join(
                                redirect_url, 
                                "?txId=#{params[:txId]}&status=#{params[:status]}&message=#{params[:message]}").to_s
                        rescue => exception
                            render_error_payload(exception.to_s)
                        end
                    end

                    private
                    def complete_service
                        Spree::Api::Dependencies.storefront_checkout_complete_service.constantize
                    end
                end
            end
        end
    end
end