# typed: true
# frozen_string_literal: true

class AddEntityIdxToCopilotEntityMemberships < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    add_index :copilot_entity_memberships, [:entity_id, :entity_type]
  end
end
