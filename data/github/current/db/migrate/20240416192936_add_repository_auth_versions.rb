class AddRepositoryAuthVersions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :repository_auth_versions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :version, unsigned: true, null: false

      t.timestamps

      t.index :repository_id, unique: true
    end
  end
end
