class AddIndexToOrganizationIdOnEnterpriseTeamOrganizationMappings < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_index :enterprise_team_organization_mappings, :organization_id
  end
end
