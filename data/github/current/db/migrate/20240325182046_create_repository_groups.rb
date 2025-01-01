class CreateRepositoryGroups < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :repository_groups, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :owner_id, unsigned: true, null: false
      t.string :owner_type, limit: 100, null: false
      t.string :group_path, limit: 255, null: false
      t.timestamps

      t.index [:owner_id, :owner_type, :group_path], unique: true, name: "index_repository_groups_owner_and_group_path"
    end
  end
end
