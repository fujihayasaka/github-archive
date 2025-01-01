class CreateGhesLicenses < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::LicensingCollab)

  def change
    create_table :ghes_licenses, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :business_id, :bigint, null: false, unsigned: true
      t.column :reference_number, "varchar(255)", null: true
      t.column :license_type, "varchar(255)", null: true
      t.column :state, "varchar(255)", null: true
      t.column :metered, :boolean, null: false, default: false
      t.column :seats, :integer, null: true
      t.column :advanced_security_enabled, :boolean, null: false, default: false
      t.column :advanced_security_seats, :integer, null: false, default: 0
      t.column :last_downloaded_at, :datetime, null: true, precision: 6
      t.column :expires_at, :datetime, null: true, precision: 6
      t.timestamps

      t.index :business_id
      t.index :expires_at
      t.index :reference_number, unique: true
    end
  end
end
