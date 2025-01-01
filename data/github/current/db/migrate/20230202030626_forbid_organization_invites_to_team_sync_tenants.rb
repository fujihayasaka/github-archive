# typed: true
# frozen_string_literal: true

class ForbidOrganizationInvitesToTeamSyncTenants < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersNotify)

  def change
    change_table :team_sync_tenants, bulk: true do |t|
      t.column :forbid_organization_invites, :boolean, null: false, default: false
      t.change :id, :bigint, unsigned: true
      t.change :organization_id, :bigint, unsigned: true
    end
  end
end
