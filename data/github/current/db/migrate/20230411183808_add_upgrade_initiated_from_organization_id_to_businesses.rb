# typed: true

class AddUpgradeInitiatedFromOrganizationIdToBusinesses < ActiveRecord::Migration[7.1]
  def change
    add_column :businesses, :upgrade_initiated_from_organization_id, :bigint, unsigned: true, null: true, after: :upgraded_from_plan
  end
end
