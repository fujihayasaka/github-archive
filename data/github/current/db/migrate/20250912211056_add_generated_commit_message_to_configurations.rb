# typed: true
# frozen_string_literal: true

class AddGeneratedCommitMessageToConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :generated_commit_message, :integer, limit: 1, null: false, default: 0, comment: "Policy for Copilot Generated Commit Message usage"
    end
  end
end
