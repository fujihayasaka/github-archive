# typed: true
# frozen_string_literal: true

class CreateSalesforceAccounts < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :salesforce_accounts, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :salesforce_id, limit: 32, index: { unique: true }, null: false
      t.string :business_segment, limit: 32
      t.string :territory_name, limit: 32
      t.text :msft_ean
      t.text :msft_pcn
      t.text :msft_tpid
      t.text :ms_sales_tpid_best_match

      t.timestamps
    end
  end
end
