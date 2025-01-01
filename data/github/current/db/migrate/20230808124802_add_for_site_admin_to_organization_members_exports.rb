# typed: true
class AddForSiteAdminToOrganizationMembersExports < ActiveRecord::Migration[7.1]
  def change
    reversible do |dir|
      change_table :organization_members_exports, bulk: true do |t|
        dir.up do
          t.boolean :for_site_admin, default: false, null: false
        end

        dir.down do
          t.remove :for_site_admin
        end
      end
    end
  end
end
