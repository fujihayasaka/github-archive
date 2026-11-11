# typed: true

class CreateRepositorySearchShortcuts < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :repository_search_shortcuts, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :creator_id, unsigned: true
      t.bigint :priority, unsigned: true
      t.string :name, null: false, default: "", limit: 1024
      t.integer :search_type, null: false, default: 0
      t.integer :icon, default: 0
      t.integer :color, default: 0
      t.blob :compressed_query
      t.blob :description
      t.boolean :pinned, null: false, default: false
      t.timestamps null: false

      t.index [:repository_id, :search_type, :priority], unique: true, name: "index_repo_search_shortcuts_on_repo_type_priority"
      t.index :creator_id, name: "index_repo_search_shortcuts_on_creator_id"
    end

    add_vindex :repository_search_shortcuts, :hash, :repository_id

    add_auto_increment :repository_search_shortcuts, :id, :repository_search_shortcuts_id_seq
  end
end
