module Spree
    class EurobankPayment < Spree::Base
        # has_secure_token

        validates :digest, presence: true, uniqueness: {case_sensitive: false}
        validates :token, presence: true, uniqueness: {case_sensitive: false}
    
        belongs_to :payment

        default_scope { order id: :desc}
    end
end