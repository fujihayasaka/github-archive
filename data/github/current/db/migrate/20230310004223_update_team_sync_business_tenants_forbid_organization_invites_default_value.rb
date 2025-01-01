# typed: true

class UpdateTeamSyncBusinessTenantsForbidOrganizationInvitesDefaultValue < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersNotify)

  def change
    change_table :team_sync_business_tenants, bulk: true do |t|
      t.change_default :forbid_organization_invites, from: false, to: true
    end
  end
end
