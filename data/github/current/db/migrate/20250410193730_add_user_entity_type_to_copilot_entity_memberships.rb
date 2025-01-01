# typed: true
# frozen_string_literal: true

class AddUserEntityTypeToCopilotEntityMemberships < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def up
    change_table :copilot_entity_memberships, bulk: true do |t|
      t.change :entity_type, "enum('User', 'EnterpriseTeam', 'Business')", null: false, default: "User"
    end
  end

  def down
    change_table :copilot_entity_memberships, bulk: true do |t|
      t.change :entity_type, "enum('Organization', 'EnterpriseTeam', 'Enterprise')", null: false, default: "Organization"
    end
  end
end
