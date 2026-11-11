# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class CreateSubIssueLists < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)
  def change
    create_table :sub_issue_lists, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :issue_id, :bigint, unsigned: true, null: false
      t.column :repository_id, :bigint, unsigned: true, null: false
      t.column :total, :integer, null: false
      t.column :completed, :integer, null: false

      t.timestamps null: false
    end

    add_vindex :sub_issue_lists, :hash, :repository_id
    add_index :sub_issue_lists, :issue_id, unique: true

    add_auto_increment(:sub_issue_lists, :id, :sub_issue_lists_id_seq)
  end
end
