# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class CreateSubIssues < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)
  def change
    create_table :sub_issues, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :source_issue_id, :bigint, unsigned: true, null: false
      t.column :source_repository_id, :bigint, unsigned: true, null: false
      t.column :target_issue_id, :bigint, unsigned: true, null: false
      t.column :priority, :bigint, unsigned: true, null: false
      t.column :actor_id, :bigint, unsigned: true, null: false
      t.column :user_hidden, :boolean, null: false, default: false

      t.timestamps null: false
    end

    add_vindex :sub_issues, :hash, :source_repository_id
    add_index :sub_issues, [:source_issue_id, :priority], unique: true
    add_index :sub_issues, [:source_issue_id, :target_issue_id], unique: true
    add_index :sub_issues, [:source_repository_id, :source_issue_id]
    add_index :sub_issues, :target_issue_id

    add_auto_increment(:sub_issues, :id, :sub_issues_id_seq)
  end
end
