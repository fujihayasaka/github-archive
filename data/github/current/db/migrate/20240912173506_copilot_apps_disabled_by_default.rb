# typed: true
# frozen_string_literal: true

class CopilotAppsDisabledByDefault < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_column_default :integration_agents, :app_type, from: "agent", to: "disabled"
  end
end
