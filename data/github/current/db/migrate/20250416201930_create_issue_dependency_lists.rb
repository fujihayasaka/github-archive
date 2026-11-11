# typed: true
# frozen_string_literal: true

class CreateIssueDependencyLists < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :issue_dependency_lists, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :issue_id, :bigint, unsigned: true, null: false
      t.column :repository_id, :bigint, unsigned: true, null: false
      t.column :blocked_by, :integer, unsigned: true, null: false
      t.column :blocking, :integer, unsigned: true, null: false

      t.timestamps null: false
      t.index :issue_id, unique: true
    end

    add_vindex :issue_dependency_lists, :hash, :repository_id
    add_auto_increment(:issue_dependency_lists, :id, :issue_dependency_lists_id_seq)
  end
end
