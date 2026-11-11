# typed: true
# frozen_string_literal: true

class AddMcpEnabledToCopilotCodeReviewRepositorySettings < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_code_review_repository_settings, bulk: true do |t|
      t.boolean :repo_mcp_enabled, null: false, default: true
    end
  end
end
