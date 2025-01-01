# typed: true
# frozen_string_literal: true

class AddCopilotEntityMembershipsIndexOnEntityTypeAndCia < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    add_index :copilot_entity_memberships, [:entity_type, :copilot_insights_activities_id], name: "index_copilot_entity_memberberships_type_on_entity_type_and_cia"
  end
end
