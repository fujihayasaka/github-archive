class CreateProximaServiceIdentity < ActiveRecord::Migration[7.2]
  def change
    create_table :proxima_service_identities, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :tenant_slug, limit: 60
      t.string :service_name, limit: 20
      t.integer :rate_limit

      t.index [:tenant_slug], unique: true
      t.timestamps
    end
  end
end
