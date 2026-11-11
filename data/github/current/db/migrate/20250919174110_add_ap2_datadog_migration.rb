# typed: true
# frozen_string_literal: true

class AddAp2DatadogMigration < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    change_table(:audit_log_datadog_sink_configurations, bulk: :true) do |t|
      t.change :site, "enum('US', 'US3', 'US5', 'EU1', 'US1-FED', 'AP1', 'AP2')", default: "US", null: false
    end
  end
end
