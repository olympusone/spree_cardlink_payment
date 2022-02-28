class CreateEurobankPaymentsTable < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_eurobank_payments do |t|
      t.references :payment
      t.string :transaction_ticket, index:{unique: true}, null: false
      t.integer  :support_reference_id, index: true
      t.string  :result_code
      t.string  :result_description
      t.string  :status_flag
      t.string  :merchant_reference
      t.integer  :package_no
      t.string  :approval_code
      t.string  :auth_status
      t.string  :uuid, index: {unique: true}, null: false
      t.string  :response_code
      t.string  :response_description
      t.string  :transaction_id

      t.timestamps
    end
  end
end
