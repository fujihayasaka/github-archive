# typed: true

class CreateIssueMentionEvents < ActiveRecord::Migration[8.2]
  self.use_connection_class ApplicationRecord::IssuesPullRequests

  def change
    create_table :issue_mention_events, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :issue_id, unsigned: true, null: false
      t.column :event_type, :tinyint, unsigned: true, null: false, comment: "type of mention, such as mention or team_mention"
      t.bigint :mentionee_id, unsigned: true, null: false, comment: "the user or team that was mentioned"
      t.bigint :subject_id, unsigned: true, null: false, comment: "the id of the specific subject where the mention happened, such as a PullRequestReviewComment id"
      t.column :subject_type, "varchar(32)", null: false, comment: "the type of the subject where the mention happened, such as PullRequestReviewComment"
      t.timestamps null: false

      t.index [:repository_id, :issue_id, :event_type, :mentionee_id, :subject_id, :subject_type], unique: true, name: "index_issue_mention_events_on_issue_and_mentionee_and_subject"
      t.index [:subject_id, :subject_type], name: "index_issue_mention_events_on_subject"
    end

    add_vindex :issue_mention_events, :hash, :repository_id
    add_auto_increment :issue_mention_events, :id, :issue_mention_events_id_seq
  end
end
