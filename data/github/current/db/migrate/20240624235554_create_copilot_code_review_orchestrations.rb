class CreateCopilotCodeReviewOrchestrations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :copilot_code_review_orchestrations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :pull_request_id, unsigned: true, null: true
      t.bigint :repository_id, unsigned: true, null: false
      t.string :type, null: false, limit: 59
      t.integer :state, null: false, default: 0
      t.string :step_name, limit: 70
      t.text :data
      t.integer :attempts, null: false, default: 0
      t.bigint :parent_id, unsigned: true, null: true
      t.string :error_message, null: true
      t.timestamps
    end

    add_vindex :copilot_code_review_orchestrations, :hash, :repository_id

    add_auto_increment :copilot_code_review_orchestrations, :id, :copilot_code_review_orchestrations_id_seq
  end
end
