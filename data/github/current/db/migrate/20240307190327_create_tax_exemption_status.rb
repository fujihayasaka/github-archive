# typed: true
# frozen_string_literal: true

class CreateTaxExemptionStatus < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    create_table :tax_exemption_statuses, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # The status here refers to the tax exemption status, could be one of "approved" or "rejected"
      t.column :status, :tinyint, null: false, default: 0
      t.bigint :customer_id, unsigned: true, index: { unique: true }, null: false

      t.timestamps
    end
  end
end
