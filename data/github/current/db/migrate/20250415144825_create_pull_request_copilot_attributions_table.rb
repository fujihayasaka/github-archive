# typed: true
# frozen_string_literal: true

class CreatePullRequestCopilotAttributionsTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    create_table :pull_request_copilot_attributions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, null: false
      t.bigint :pull_request_id, unsigned: true, null: false
      t.column :repository_id, :bigint, null: true, unsigned: true
      t.timestamps

      t.index [:pull_request_id, :repository_id, :user_id], unique: true, name: "index_pull_request_copilot_attributions_on_pr_repo_user"
    end

    add_vindex :pull_request_copilot_attributions, :hash, :repository_id
    add_auto_increment :pull_request_copilot_attributions, :id, :pull_request_copilot_attributions_id_seq
  end
end
