class CreateEurobankPaymentsTable < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_eurobank_payments, :status, :string
  end
end
