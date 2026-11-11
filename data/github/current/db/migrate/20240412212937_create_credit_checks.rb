# typed: true
# frozen_string_literal: true

class CreateCreditChecks < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    create_table :credit_checks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # The status here refers to the credit check verification status, could be one of "approved" or "rejected" or "pending approval"
      t.column :status, :tinyint, null: false, default: 0, index: true
      t.column :request_id, :string, limit: 32, null: false, index: true
      t.bigint :customer_id, unsigned: true, index: { unique: true }, null: false

      t.timestamps
    end
  end
end
