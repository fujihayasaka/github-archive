class EnterpriseTeamsAddSyncToOrganizations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :enterprise_teams, :sync_to_organizations, "enum('disabled', 'all')", null: false, default: "disabled"
  end
end
