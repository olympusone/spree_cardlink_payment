module Spree::PaymentMethodDecorator
    def self.prepended(base)
        base.preference :new_ticket_url, :string, default: 'https://eurocommerce-test.cardlink.gr/vpos/shophandlermpi'
        base.preference :merchant_id, :string
        base.preference :shared_secret, :string
    end

    protected
    def public_preference_keys
        [:new_ticket_url, :merchant_id, :shared_secret]
    end
end
  
::Spree::PaymentMethod.prepend(Spree::PaymentMethodDecorator)