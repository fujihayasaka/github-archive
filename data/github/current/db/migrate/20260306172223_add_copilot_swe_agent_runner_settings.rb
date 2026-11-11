# typed: true
# frozen_string_literal: true

class AddCopilotSweAgentRunnerSettings < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_swe_agent_configuration, bulk: true do |t|
      t.column :runner_type, 'enum("standard", "labeled")', null: false, default: "standard", comment: "The default runner type for copilot runs.  Standard used a default runner, labeled uses a series of labels"

      t.column :runner_group_name, :string, null: false, default: "", comment: "The runner group to use, when runner_type is of type 'labeled'"
      t.column :runner_labels, :string, null: false, default: "", comment: "The runner labels to use, when runner_type is of type 'labeled'. A comma-delimited list of labels"

      t.column :allow_repo_custom_runner, :boolean, null: false, default: true, comment: "Allows repositories to override the organization runner setting"
    end
  end
end
