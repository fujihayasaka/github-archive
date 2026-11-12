class AddVisibilityScopeToVulnerableVersionRanges < ActiveRecord::Migration[8.0]
  def change
    add_column :dg_vulnerable_version_ranges, :visibility_scope, :string, limit: 20, default: "open_source", comment: "open_source or innersource"

    add_index :dg_vulnerable_version_ranges, :visibility_scope, name: "index_dg_vuln_version_ranges_on_visibility_scope"
  end
end
