class CreateEurobankPaymentsTable < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_eurobank_payments do |t|
      t.references :payment
      
      t.string :digest, index: true, null: false
      t.string :uuid, index: {unique: true}, null: false
      t.string :message
      t.integer :tx_id
      t.string :payment_ref

      t.timestamps
    end
  end
end
