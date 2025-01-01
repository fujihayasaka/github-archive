# typed: true
# frozen_string_literal: true

class CreateBatchRefUpdateRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    # Following the pattern of the `merge_commit_requests` table, we won't require an auto incrementing integer
    # as this table is never queried by ID.
    create_table :ref_update_requests, primary_key: [:repository_id, :ref_name, :created_at], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t| # rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :pull_request_id, unsigned: true, null: false, comment: "pull request associated with the request"
      t.boolean :processing, null: false, default: false, comment: "the state of the request to perform ref updates"
      t.column :ref_name, "varbinary(1024)", null: false, comment: "the git ref to be updated"
      t.column :before_sha, "binary(20)", null: true, comment: "before sha of the ref update"
      t.column :after_sha, "binary(20)", null: false, comment: "after sha of the ref update"
      t.integer :attempts, null: false, default: 0, comment: "attempt number of request"
      t.timestamps null: false

      t.index [:repository_id, :processing, :ref_name], name: "index_repo_id_processing_refname_on_ref_update_requests", unique: true
    end

    add_vindex :ref_update_requests, :hash, :repository_id
  end
end
