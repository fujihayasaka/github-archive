# typed: true
# frozen_string_literal: true

class CreatePullRequestGroups < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::IssuesPullRequests

  def change
    create_table :pull_request_groups, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :pull_request_id, unsigned: true, null: false
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :actor_id, unsigned: true, null: false

      t.string :base_commit_oid, limit: 64, null: false
      t.string :head_commit_oid, limit: 64, null: false
      t.string :name, limit: 128, null: false
      t.string :description, null: true

      t.integer :priority, unsigned: true, null: false, default: 0
      t.integer :confidence, unsigned: true, null: false, default: 0
      t.integer :bug_risk, unsigned: true, null: false, default: 0

      t.json :hunk_positions, null: false

      t.timestamps null: false

      t.index [:repository_id, :pull_request_id, :base_commit_oid, :head_commit_oid]
    end

    add_vindex :pull_request_groups, :hash, :repository_id
    add_auto_increment :pull_request_groups, :id, :pull_request_groups_id_seq
  end
end
