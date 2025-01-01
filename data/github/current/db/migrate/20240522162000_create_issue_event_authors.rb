class CreateIssueEventAuthors < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :issue_event_authors, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :author_id, unsigned: true, null: false
      t.bigint :issue_event_id, unsigned: true, null: false
      t.bigint :repository_id, unsigned: true, null: false
      t.boolean :user_hidden, null: false, default: false

      t.timestamps
    end

    add_vindex :issue_event_authors, :hash, :repository_id

    add_index :issue_event_authors, :author_id
    add_index :issue_event_authors, :issue_event_id

    add_auto_increment :issue_event_authors, :id, :issue_event_authors_id_seq
  end
end
