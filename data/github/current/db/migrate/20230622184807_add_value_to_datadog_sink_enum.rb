# typed: true

class AddValueToDatadogSinkEnum < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    change_table(:audit_log_datadog_sink_configurations, bulk: :true) do |t|
      t.change :site, "enum('US', 'US3', 'US5', 'EU1', 'US1-FED', 'AP1')", default: "US", null: false
    end
  end
end
