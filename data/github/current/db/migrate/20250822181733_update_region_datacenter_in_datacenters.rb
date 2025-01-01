# typed: true

class UpdateRegionDatacenterInDatacenters < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Spokes)

  def up
    change_table :datacenters, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :datacenter, :string, limit: 255, null: false
      t.change :region, :string, limit: 255, null: false
    end
  end

  def down
    change_table :datacenters, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :datacenter, :string, limit: 8, null: false
      t.change :region, :string, limit: 8, null: false
    end
  end
end
