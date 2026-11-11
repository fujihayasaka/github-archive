# typed: true
# frozen_string_literal: true

class DropPrDiffChatsColumnFromCopilotConfigurationsTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def up
    remove_column :copilot_configurations, :pr_diff_chats, :integer
  end

  def down
    add_column :copilot_configurations, :pr_diff_chats, :integer, null: false, default: 0
  end
end
