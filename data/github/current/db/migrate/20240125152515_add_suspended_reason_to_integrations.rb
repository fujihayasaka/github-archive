class AddSuspendedReasonToIntegrations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    add_column :integrations, :suspended_reason, :string, limit: 255
  end
end
