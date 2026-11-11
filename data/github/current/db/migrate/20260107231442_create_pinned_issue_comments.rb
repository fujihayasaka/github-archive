# typed: true

class CreatePinnedIssueComments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :pinned_issue_comments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :issue_id, unsigned: true, null: false, comment: "References the issue on which the comment is pinned"
      t.bigint :issue_comment_id, unsigned: true, null: false, comment: "References the pinned comment on the issue"
      t.bigint :repository_id, unsigned: true, null: false, comment: "References the repository containing the issue and comment"
      t.bigint :pinned_by_id, unsigned: true, null: false, comment: "References the user who pinned the comment"

      t.timestamps null: false, precision: 6

      t.index :issue_id, unique: true
    end

    add_vindex :pinned_issue_comments, :hash, :repository_id
    add_vindex :pinned_issue_comments, :issues_id_ks_idx, :issue_id
    add_vindex :pinned_issue_comments, :issue_comments_id_ks_idx, :issue_comment_id

    add_auto_increment :pinned_issue_comments, :id, :pinned_issue_comments_id_seq
  end
end
