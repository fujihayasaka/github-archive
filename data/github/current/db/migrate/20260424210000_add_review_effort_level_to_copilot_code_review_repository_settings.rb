# typed: true
# frozen_string_literal: true

class AddReviewEffortLevelToCopilotCodeReviewRepositorySettings < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_code_review_repository_settings, bulk: true do |t|
      t.column :repo_review_effort_level, :tinyint, null: false, default: 0
    end
  end
end
