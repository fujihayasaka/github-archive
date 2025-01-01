# typed: true
class CreateBusinessLicenseUsages < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :business_license_usages, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :business_id, unsigned: true, null: false, index: true

      t.integer :consumed_enterprise_licenses, unsigned: true, null: false, default: 0
      t.integer :consumed_volume_licenses, unsigned: true, null: false, default: 0

      t.datetime :generated_at, precision: 6, null: false

      t.timestamps
    end
  end
end
