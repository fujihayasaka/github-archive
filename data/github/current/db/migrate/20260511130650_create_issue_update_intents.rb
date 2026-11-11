class CreateIssueUpdateIntents < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :issue_update_intents, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :issue_id, unsigned: true, null: false
      t.bigint :issue_event_id, unsigned: true
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :actor_id, unsigned: true
      t.string :rationale, limit: 280
      t.column :state, "tinyint unsigned", null: false, default: 0
      t.string :action, limit: 50, null: false
      t.bigint :target_id, unsigned: true
      t.string :target_value, limit: 255
      t.column :confidence, "tinyint unsigned"
      t.bigint :resolved_by, unsigned: true

      t.timestamps

      t.index [:repository_id, :issue_event_id], unique: true, name: "index_issue_update_intents_on_repo_and_event_id"
      t.index [:repository_id, :issue_id, :created_at], name: "index_issue_update_intents_on_repo_issue_created"
      t.index [:repository_id, :state, :created_at], name: "index_issue_update_intents_on_repo_state_created"
    end

    add_vindex :issue_update_intents, :hash, :repository_id

    add_auto_increment :issue_update_intents, :id, :issue_update_intents_id_seq
  end
end
