# typed: true
# frozen_string_literal: true

class AddIndexCopilotConfigPendingDowngrade < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    add_index :copilot_configurations, [:configurable_type, :pending_plan_downgrade_date], name: "idx_configurable_type_pending_plan_downgrade_date"
  end
end
