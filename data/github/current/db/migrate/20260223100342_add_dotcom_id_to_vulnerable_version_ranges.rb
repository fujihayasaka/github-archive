# typed: true
# frozen_string_literal: true

# Adds dotcom_id to vulnerable_version_ranges to prevent ID collisions with dotcom
# during vulnerabilities GHES/Proxima sync.

# rubocop:disable GitHub/AvoidRedundantIndex
class AddDotcomIdToVulnerableVersionRanges < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)
  def up
    change_table(:vulnerable_version_ranges, bulk: true) do |t|
      t.unsigned_bigint :dotcom_id, null: true
      t.remove_index :vulnerability_id, name: "index_vulnerable_version_ranges_on_vulnerability_id"
      t.index [:vulnerability_id, :dotcom_id], name: "index_vulnerable_version_ranges_on_vuln_id_and_dotcom_id"
    end
  end

  def down
    remove_index :vulnerable_version_ranges, name: "index_vulnerable_version_ranges_on_vuln_id_and_dotcom_id"
    remove_column :vulnerable_version_ranges, :dotcom_id
    add_index :vulnerable_version_ranges, :vulnerability_id, name: "index_vulnerable_version_ranges_on_vulnerability_id"
  end
end
# rubocop:enable GitHub/AvoidRedundantIndex
