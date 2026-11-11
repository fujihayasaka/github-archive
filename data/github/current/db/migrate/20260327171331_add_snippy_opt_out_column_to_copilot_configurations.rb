# typed: true
# frozen_string_literal: true

class AddSnippyOptOutColumnToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :snippy_opt_out, :integer, limit: 1, null: false, default: 0, comment: "Whether to opt out of snippy"
    end
  end
end
