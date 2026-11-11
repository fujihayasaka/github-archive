class CreateSoftDeletedOrganizations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :soft_deleted_organizations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :organization_id, unsigned: true, null: false
      t.datetime :created_at, null: false, precision: 6
    end
  end
end
