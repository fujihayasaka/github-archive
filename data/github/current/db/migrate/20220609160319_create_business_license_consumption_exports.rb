# typed: true
class CreateBusinessLicenseConsumptionExports < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def change
    create_table :business_license_consumption_exports, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column   :actor_id, :bigint, unsigned: true, null: false
      t.column   :business_id, :bigint, unsigned: true, null: false
      t.column   :token, :string, null: false, limit: 36, index: { unique: true }
      t.column   :format, "enum('csv', 'json')", null: false, default: "csv"
      t.datetime :created_at, null: false, precision: 6
      t.datetime :updated_at, null: false, precision: 6
    end
  end
end
