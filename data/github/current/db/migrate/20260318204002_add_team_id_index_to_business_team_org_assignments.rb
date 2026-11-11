# typed: true
# frozen_string_literal: true

class AddTeamIdIndexToBusinessTeamOrgAssignments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_index :business_team_org_assignments, :team_id, name: "index_business_team_org_assignments_on_team_id", if_not_exists: true
  end
end
