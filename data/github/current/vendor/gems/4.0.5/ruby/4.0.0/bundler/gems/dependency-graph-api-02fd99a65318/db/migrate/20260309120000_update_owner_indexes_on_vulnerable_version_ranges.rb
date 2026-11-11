class UpdateOwnerIndexesOnVulnerableVersionRanges < ActiveRecord::Migration[8.0]
  def change
    add_index :dg_vulnerable_version_ranges,
              [:owner_business_id, :owner_org_id],
              name: "index_dg_vuln_version_ranges_on_owner_business_and_org_id",
              if_not_exists: true

    remove_index :dg_vulnerable_version_ranges,
                 name: "index_dg_vuln_version_ranges_on_owner_business_id",
                 if_exists: true
    remove_index :dg_vulnerable_version_ranges,
                 name: "index_dg_vuln_version_ranges_on_owner_org_id",
                 if_exists: true
  end
end
