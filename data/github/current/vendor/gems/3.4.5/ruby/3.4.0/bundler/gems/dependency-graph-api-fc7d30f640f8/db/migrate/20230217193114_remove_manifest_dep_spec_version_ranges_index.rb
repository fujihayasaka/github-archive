class RemoveManifestDepSpecVersionRangesIndex < ActiveRecord::Migration[6.0]
  def change
    remove_index :dg_manifest_dependencies, column:  [:package_name, :encoded_lower_bound, :encoded_upper_bound], name: :index_manifest_dep_spec_version_ranges
  end
end
