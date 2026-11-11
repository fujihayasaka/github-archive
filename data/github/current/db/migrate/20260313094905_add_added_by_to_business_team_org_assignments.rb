# typed: true
# frozen_string_literal: true

class AddAddedByToBusinessTeamOrgAssignments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :business_team_org_assignments, bulk: true do |t|
      t.column :added_by, :tinyint, null: true, default: 0
      t.index [:organization_id, :added_by, :team_id], name: "index_business_team_org_assignments_on_org_added_by_team"
    end
  end
end
