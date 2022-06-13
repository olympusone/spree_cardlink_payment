module Spree::PaymentMethodDecorator
    def self.prepended(base)
        base.preference :new_ticket_url, :string
        base.preference :merchant_id, :string
        base.preference :shared_secret, :string

        base.preference :confirm_url, :string
        base.preference :cancel_url, :string
    end

    protected
    def public_preference_keys
        [:new_ticket_url, :merchant_id, :confirm_url, :cancel_url]
    end
end
  
::Spree::PaymentMethod.prepend(Spree::PaymentMethodDecorator)