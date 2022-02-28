module Spree
    class EurobankPayment < Spree::Base
        validates :transaction_ticket, presence: true, uniqueness: {case_sensitive: false}
        validates :support_reference_id, presence: true, uniqueness: {case_sensitive: false}, on: :update
    
        belongs_to :payment

        default_scope { order id: :desc}
    end
end