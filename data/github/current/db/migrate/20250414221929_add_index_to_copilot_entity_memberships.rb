# typed: true
# frozen_string_literal: true

class AddIndexToCopilotEntityMemberships < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_entity_memberships, bulk: true do |t|
      t.index :copilot_insights_activities_id, name: "index_copilot_insights_activities_id"
      t.index :platform_insights_activities_id, name: "index_platform_insights_activities_id"
    end
  end
end
