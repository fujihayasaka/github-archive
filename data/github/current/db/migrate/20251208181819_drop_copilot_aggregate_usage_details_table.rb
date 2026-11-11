# typed: true
# frozen_string_literal: true

class DropCopilotAggregateUsageDetailsTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    drop_table :copilot_aggregate_usage_details, if_exists: true
  end
end
