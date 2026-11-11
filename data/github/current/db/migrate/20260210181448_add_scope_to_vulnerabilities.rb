# typed: true
# frozen_string_literal: true

class AddScopeToVulnerabilities < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    change_table :vulnerabilities, bulk: true do |t|
      t.string :visibility_scope, limit: 20, default: "open_source", comment: "open_source or innersource"
      t.unsigned_bigint :owner_business_id, null: true, default: nil
      t.unsigned_bigint :owner_org_id, null: true, default: nil
      t.string :external_id, limit: 2048, null: true, default: nil
    end

    add_index :vulnerabilities, [:owner_business_id], name: "index_vulnerabilities_on_owner_business_id"
    add_index :vulnerabilities, [:owner_org_id], name: "index_vulnerabilities_on_owner_org_id"
  end
end
