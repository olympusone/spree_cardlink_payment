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
                            lang = params[:lang] || Spree::Store.current.default_locale
                            
                            digest_body = {
                                version: 2,
                                mid: preferences[:merchant_id],
                                lang: lang,
                                orderid: orderid,
                                orderDesc: spree_current_order.number,
                                orderAmount: payment.amount, 
                                currency: currency,
                                billCountry: bill_address.country.iso,
                                billZip: bill_address.zipcode,
                                billCity: bill_address.city,
                                billAddress: bill_address.address1,
                                confirmUrl: confirm_url,
                                cancelUrl: cancel_url,
                            }

                            string = [
                                *digest_body.values,
                                preferences[:shared_secret],
                            ].join.strip

                            digest = Base64.encode64(Digest::SHA256.digest string).strip

                            cardlink_payment = payment.cardlink_payments.create!(
                                digest: digest, 
                                orderid: orderid
                            )

                            digest_body[:digest] = digest
                            
                            render json: digest_body
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

                            # TODO make it more efficient
                            lang = params[:extData] ? CGI::parse(params[:extData])["var1"][0] : Spree::Store.current.default_locale
                            failure_url = URI.join(preferences[:app_host], "/#{lang}", "/checkout/failure")

                            redirect_to URI::join(
                                failure_url, 
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

                            # TODO make it more efficient
                            lang = params[:extData] ? CGI::parse(params[:extData])["var1"][0] : Spree::Store.current.default_locale

                            if ['AUTHORIZED', 'CAPTURED'].include?(params[:status])
                                payment.complete
                                complete_service.call(order: payment.order)

                                redirect_url = URI.join(preferences[:app_host], "/#{lang}", "/checkout/success")
                            else
                                payment.failure

                                redirect_url = URI.join(preferences[:app_host], "/#{lang}", "/checkout/failure")
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