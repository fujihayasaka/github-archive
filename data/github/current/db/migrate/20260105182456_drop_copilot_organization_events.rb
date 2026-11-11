# typed: true
# frozen_string_literal: true

class DropCopilotOrganizationEvents < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    drop_table :copilot_organization_events, if_exists: true
  end
end
