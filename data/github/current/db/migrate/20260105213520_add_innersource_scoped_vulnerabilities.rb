# typed: strict
# frozen_string_literal: true

class AddInnersourceScopedVulnerabilities < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  sig { void }
  def up
    change_table :scoped_vulnerabilities, bulk: true do |t|
      t.bigint :owner_business_id, null: true, unsigned: true, default: nil
      t.bigint :owner_org_id, null: true, unsigned: true, default: nil
      t.string :external_id, limit: 2048, null: true
      t.change :advisory_repository_id, :bigint, unsigned: true, null: true, default: nil
    end

    add_index :scoped_vulnerabilities, [:owner_business_id], name: "index_scoped_vuln_on_owner_business_id"
    add_index :scoped_vulnerabilities, [:owner_org_id], name: "index_scoped_vuln_on_owner_org_id"
    add_index :scoped_vulnerabilities, [:external_id], name: "index_scoped_vuln_on_external_id", length: 256
  end

  sig { void }
  def down
    remove_index :scoped_vulnerabilities, name: "index_scoped_vuln_on_owner_business_id", if_exists: true
    remove_index :scoped_vulnerabilities, name: "index_scoped_vuln_on_owner_org_id", if_exists: true
    remove_index :scoped_vulnerabilities, name: "index_scoped_vuln_on_external_id", if_exists: true

    change_table :scoped_vulnerabilities, bulk: true do |t|
      t.remove :owner_business_id
      t.remove :owner_org_id
      t.remove :external_id
      t.change :advisory_repository_id, :bigint, unsigned: true, null: false, default: 0
    end
  end
end
