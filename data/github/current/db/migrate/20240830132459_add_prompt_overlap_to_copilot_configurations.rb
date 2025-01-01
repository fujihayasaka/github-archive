# typed: true

class AddPromptOverlapToCopilotConfigurations < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.integer :prompt_overlap, limit: 1, null: false, default: 0, comment: "Whether to show code suggestions from public sources when the response is contained within the prompt"
    end
  end
end
