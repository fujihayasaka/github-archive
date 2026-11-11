# typed: true
# frozen_string_literal: true

class AddBusinessIdToBusinessTeamOrgAssignments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :business_team_org_assignments, bulk: true do |t|
      t.column :business_id, :bigint, unsigned: true, null: true

      t.index :business_id, name: "index_business_team_org_assignments_on_business_id"
    end
  end
end
