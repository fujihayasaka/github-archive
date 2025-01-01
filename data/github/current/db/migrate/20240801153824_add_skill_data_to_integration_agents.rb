class AddSkillDataToIntegrationAgents < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :integration_agents, bulk: true do |t|
      t.column :skill_data, :json
      t.column :app_type, "enum('disabled', 'agent', 'skill')", default: "agent", null: false
    end
  end
end
