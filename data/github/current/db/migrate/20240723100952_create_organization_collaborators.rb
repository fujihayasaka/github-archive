class CreateOrganizationCollaborators < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    create_table :organization_collaborators, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :user_id, :bigint, unsigned: true, null: false
      t.column :organization_id, :bigint, unsigned: true, null: false
      t.column :business_id, :bigint, unsigned: true, null: true

      t.index [:user_id, :organization_id, :business_id], name: :index_organization_collaborators_on_user_organization_business, unique: true

      t.column :public, :boolean, null: false, default: false, index: true
      t.column :public_only_forks, :boolean, null: false, default: false, index: true
      t.column :private, :boolean, null: false, default: false, index: true
      t.column :private_only_forks, :boolean, null: false, default: false, index: true

      t.timestamps
    end
  end
end
