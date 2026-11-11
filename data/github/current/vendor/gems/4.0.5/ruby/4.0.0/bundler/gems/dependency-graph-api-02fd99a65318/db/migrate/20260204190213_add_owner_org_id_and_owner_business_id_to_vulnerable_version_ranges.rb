class AddOwnerOrgIdAndOwnerBusinessIdToVulnerableVersionRanges < ActiveRecord::Migration[8.0]
  def change
    add_column :dg_vulnerable_version_ranges, :owner_business_id, :unsigned_bigint
    add_column :dg_vulnerable_version_ranges, :owner_org_id, :unsigned_bigint

    add_index :dg_vulnerable_version_ranges, :owner_business_id, name: "index_dg_vuln_version_ranges_on_owner_business_id"
    add_index :dg_vulnerable_version_ranges, :owner_org_id, name: "index_dg_vuln_version_ranges_on_owner_org_id"
  end
end
