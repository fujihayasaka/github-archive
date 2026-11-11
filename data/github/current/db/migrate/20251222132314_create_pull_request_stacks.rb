# typed: true
# frozen_string_literal: true

class CreatePullRequestStacks < ActiveRecord::Migration[8.2]
  use_connection_class ApplicationRecord::IssuesPullRequests

  def change
    create_table :pull_request_stacks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.column :base_ref, "varbinary(1024)", null: false
      t.timestamps null: false
    end

    add_vindex :pull_request_stacks, :hash, :repository_id
    add_auto_increment :pull_request_stacks, :id, :pull_request_stacks_id_seq
  end
end
