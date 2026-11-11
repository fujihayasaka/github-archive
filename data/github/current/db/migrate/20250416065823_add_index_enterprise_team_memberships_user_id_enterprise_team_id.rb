# typed: true

class AddIndexEnterpriseTeamMembershipsUserIdEnterpriseTeamId < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_index :enterprise_team_memberships, [:user_id, :enterprise_team_id]
  end
end
