# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ArchivedTable
class AddOwnerTypeAndOwnerIdToVulnerabilities < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    change_table :vulnerabilities, bulk: true do |t|
      t.column :owner_type, "varchar(20)", null: true, default: nil, comment: "Business or Organization"
      t.unsigned_bigint :owner_id, null: true, default: nil
    end

    add_index :vulnerabilities, [:owner_id, :owner_type], name: "index_vulnerabilities_on_owner_id_and_owner_type"
  end
end
# rubocop:enable GitHub/ArchivedTable
