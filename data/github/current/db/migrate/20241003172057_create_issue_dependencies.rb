# typed: true

class CreateIssueDependencies < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :issue_dependencies, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :source_issue_id, :bigint, unsigned: true, null: false
      t.column :source_repository_id, :bigint, unsigned: true, null: false
      t.column :target_issue_id, :bigint, unsigned: true, null: false
      t.column :target_repository_id, :bigint, unsigned: true, null: false
      t.column :dependency_type, :tinyint, unsigned: true, null: false
      t.column :actor_id, :bigint, unsigned: true, null: false
      t.column :user_hidden, :boolean, null: false, default: false
      t.timestamps null: false

      t.index [:source_issue_id, :target_issue_id, :dependency_type], unique: true, name: "index_issue_dependencies_on_source_target_type"
      t.index [:source_issue_id, :dependency_type, :created_at], name: "index_issue_dependencies_on_source_type_created"
      t.index [:source_repository_id, :source_issue_id], name: "index_issue_dependencies_on_source_repository_source_issue"
      t.index [:target_issue_id], name: "index_issue_dependencies_on_target_issue"
      t.index [:actor_id, :user_hidden], name: "index_issue_dependencies_on_actor_user_hidden"
    end

    add_vindex :issue_dependencies, :hash, :source_repository_id
    add_auto_increment(:issue_dependencies, :id, :issue_dependencies_id_seq)
  end
end
