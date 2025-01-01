# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys

class CreateMergeCommitRequests < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :merge_commit_requests, primary_key: [:repository_id, :pull_request_id, :created_at], charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :pull_request_id, unsigned: true, null: false
      t.boolean :processing, null: false, default: false, comment: "the state of the request to create a merge commit"
      t.timestamps null: false

      t.index [:repository_id, :processing, :pull_request_id], name: "index_repo_id_processing_pull_id_on_merge_commit_requests", unique: true
    end

    add_vindex :merge_commit_requests, :hash, :repository_id
    add_vindex :merge_commit_requests, :pull_requests_id_ks_idx, :pull_request_id
  end
end
