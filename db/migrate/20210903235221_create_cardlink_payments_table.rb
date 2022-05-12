class CreateCardlinkPaymentsTable < ActiveRecord::Migration[6.1]
  def change
    create_table :spree_cardlink_payments do |t|
      t.references :payment
      
      t.string :digest, index: {unique: true}, null: false
      t.string :orderid, index: {unique: true}, null: false
      t.string :message
      t.bigint :tx_id
      t.string :payment_ref
      t.string :status

      t.timestamps
    end
  end
end
