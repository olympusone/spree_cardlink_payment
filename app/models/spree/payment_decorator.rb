module Spree::PaymentDecorator
    def self.prepended(base)
      base.has_many :eurobank_payments, dependent: :destroy
    end
end
  
Spree::Payment.prepend Spree::PaymentDecorator
  