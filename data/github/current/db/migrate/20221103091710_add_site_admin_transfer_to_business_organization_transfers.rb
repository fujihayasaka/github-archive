# typed: true
class AddSiteAdminTransferToBusinessOrganizationTransfers < ActiveRecord::Migration[7.1]
  def change
    reversible do |dir|
      change_table :business_organization_transfers, bulk: true do |t|
        dir.up do
          t.boolean :site_admin_transfer, default: false, null: false
        end

        dir.down do
          t.remove :site_admin_transfer
        end
      end
    end
  end
end
