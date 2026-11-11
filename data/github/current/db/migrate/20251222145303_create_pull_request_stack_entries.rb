# typed: true
# frozen_string_literal: true

class CreatePullRequestStackEntries < ActiveRecord::Migration[8.2]
  use_connection_class ApplicationRecord::IssuesPullRequests

  def change
    create_table :pull_request_stack_entries, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :stack_id, unsigned: true, null: false
      t.bigint :pull_request_id, unsigned: true, null: false
      t.integer :position, null: false
      t.timestamps null: false

      t.index [:repository_id, :stack_id, :position]
      t.index [:repository_id, :pull_request_id]
    end

    add_vindex :pull_request_stack_entries, :hash, :repository_id
    add_auto_increment :pull_request_stack_entries, :id, :pull_request_stack_entries_id_seq
  end
end
