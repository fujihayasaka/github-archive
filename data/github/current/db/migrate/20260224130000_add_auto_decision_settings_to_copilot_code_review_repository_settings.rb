# typed: true
# frozen_string_literal: true

class AddAutoDecisionSettingsToCopilotCodeReviewRepositorySettings < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_code_review_repository_settings, bulk: true do |t|
      t.boolean :repo_auto_approve_enabled, null: false, default: false
      t.boolean :repo_auto_reject_enabled, null: false, default: false
    end
  end
end
