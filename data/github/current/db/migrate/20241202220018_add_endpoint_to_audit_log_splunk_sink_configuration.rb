# typed: true

class AddEndpointToAuditLogSplunkSinkConfiguration < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    add_column :audit_log_splunk_sink_configurations, :endpoint, :string, default: "/services/collector", null: false
  end
end
