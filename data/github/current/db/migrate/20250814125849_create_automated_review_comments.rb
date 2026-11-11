# typed: true

class CreateAutomatedReviewComments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    create_table :automated_review_comments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.timestamps

      t.references :repository, null: false, unsigned: true, index: false
      t.references :pull_request, null: false, unsigned: true, index: false
      t.references :pull_request_review_comment, null: false, unsigned: true

      t.column :source, :tinyint, null: false, unsigned: true
      t.string :resource_id, null: false, limit: 255
      t.column :severity, :tinyint, null: false, unsigned: true, default: 0
      t.column :security_severity, :tinyint, null: false, unsigned: true, default: 0

      t.column :title, "varbinary(1024)", null: true
      t.blob :message, null: true

      t.column :fixed_at, :datetime, precision: 6, null: true
      t.column :dismissed_at, :datetime, precision: 6, null: true
      t.string :dismissal_reason, null: true, limit: 50

      t.column :suggestion_state, :tinyint, null: false, unsigned: true, default: 0
      t.json :suggestion, null: true
      t.string :suggestion_error_message, null: true, limit: 255

      t.json :metadata

      t.index [:repository_id, :pull_request_review_comment_id], name: "index_arc_on_pull_request_review_comment_id", unique: true
      t.index [:repository_id, :pull_request_id, :pull_request_review_comment_id], name: "index_arc_on_repo_pr_prc"
      t.index [:source, :resource_id], name: "index_arc_on_source_resource_id"
    end

    add_vindex :automated_review_comments, :hash, :repository_id
    add_auto_increment :automated_review_comments, :id, :automated_review_comments_id_seq
  end
end
