# typed: true
# frozen_string_literal: true

class CreateBusinessTeamOrgAssignmentJoinTable < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users) # rubocop:disable GitHub/EnsureDomainIsolationInMigration

  def change
    create_table :business_team_org_assignments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|  # rubocop:disable GitHub/EnsureDomainIsolationInMigration
      t.column :team_id, :bigint, unsigned: true, null: false
      t.column :organization_id, :bigint, unsigned: true, null: false
      t.timestamps

      t.index [:organization_id, :team_id], unique: true, name: "index_business_team_org_assignments_on_organization_and_team"
    end
  end
end
