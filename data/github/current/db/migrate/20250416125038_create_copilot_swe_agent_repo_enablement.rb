# typed: true
# frozen_string_literal: true

class CreateCopilotSweAgentRepoEnablement < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :copilot_swe_agent_repo_enablements, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint   :owner_id, null: false, unsigned: true, index: true, comment: "The ID of the owner of the repository"
      t.bigint   :repository_id, null: false, unsigned: true, index: true, comment: "The ID of the enabled repository"
      t.bigint   :enabled_by_id, null: false, unsigned: true, comment: "The ID of the user that enabled the feature for this repository"
      t.datetime :created_at, null: false, precision: 6, comment: "The time when the feature was enabled for this repository"
    end
  end
end
