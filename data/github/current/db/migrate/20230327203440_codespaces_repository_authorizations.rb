# typed: true

class CodespacesRepositoryAuthorizations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    create_table :codespaces_repository_authorizations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :user_id, :bigint, unsigned: true, null: false
      t.column :repository_id, :bigint, unsigned: true, null: false
      t.column :access_type, "enum('read','write')", null: true
      t.timestamps
    end

    add_index :codespaces_repository_authorizations, [:user_id, :repository_id], unique: true, name: "idx_codespaces_authorizations_on_user_and_repository"
  end
end
