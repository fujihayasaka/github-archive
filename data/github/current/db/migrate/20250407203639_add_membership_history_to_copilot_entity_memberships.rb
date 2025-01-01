# typed: true
# frozen_string_literal: true

class AddMembershipHistoryToCopilotEntityMemberships < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def up
    change_table :copilot_entity_memberships, bulk: true do |t|
      t.column :membership_history, "VARBINARY(128)"
      t.change :entity_type, "enum('Organization', 'EnterpriseTeam', 'Enterprise')", null: false, default: "Organization"
    end
  end

  def down
    change_table :copilot_entity_memberships, bulk: true do |t|
      t.remove :membership_history
      t.change :entity_type, :tinyint, unsigned: true, null: false, default: 0
    end
  end
end
