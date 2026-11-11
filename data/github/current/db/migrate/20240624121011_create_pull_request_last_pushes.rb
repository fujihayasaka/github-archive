class CreatePullRequestLastPushes < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :pull_request_last_pushes, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :pull_request_id, unsigned: true, null: false
      t.bigint :push_id, unsigned: true, null: false
      t.string :head_sha, limit: 64, null: false

      t.timestamps null: false

      t.index [:repository_id, :pull_request_id], unique: true
    end

    add_vindex :pull_request_last_pushes, :hash, :repository_id
    add_vindex :pull_request_last_pushes, :pull_requests_id_ks_idx, :pull_request_id

    add_auto_increment(:pull_request_last_pushes, :id, :pull_request_last_pushes_id_seq)
  end
end
