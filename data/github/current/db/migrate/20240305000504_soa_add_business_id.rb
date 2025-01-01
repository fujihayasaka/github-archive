# typed: true

# rubocop:disable GitHub/AvoidTypeBeforeId

class SoaAddBusinessId < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    change_table :soa_repositories, bulk: true do |t|
      t.column :owner_id, :bigint, unsigned: true, null: false, default: 0
      t.column :owner_type, "enum('USER', 'ORGANIZATION')", null: false, default: "ORGANIZATION"
      t.column :business_id, :bigint, unsigned: true, null: true

      t.index [:business_id, :owner_id, :owner_type, :archived, :name], name: "index_soa_repositories_on_business_owner_type_archived_name"
      t.index [:business_id, :owner_id, :owner_type, :archived, :visibility, :name], name: "index_soa_repositories_on_business_owner_type_arch_vis_name"
    end
  end
end
