# typed: true

class CreateBusinessOrganizationTransfers < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def change
    create_table :business_organization_transfers, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :organization_id, unsigned: true, null: false, index: true
      t.bigint :from_business_id, unsigned: true, null: false, index: true
      t.bigint :to_business_id, unsigned: true, null: false, index: true
      t.bigint :actor_id, unsigned: true, null: false
      t.datetime :completed_at, precision: 6, null: true
      t.datetime :failed_at, precision: 6, null: true
      t.string :failed_reason, null: true

      t.timestamps
    end
  end
end
