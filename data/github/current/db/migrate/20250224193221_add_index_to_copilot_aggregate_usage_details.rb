# typed: true
# frozen_string_literal: true

class AddIndexToCopilotAggregateUsageDetails < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    add_index :copilot_aggregate_usage_details, [:user_id, :updated_at], name: "idx_copilot_aggregate_usage_details_id_and_updated_at"
  end
end
