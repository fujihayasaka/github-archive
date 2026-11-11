# typed: true
# frozen_string_literal: true

class AddOverrideToColdNetworks < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Spokes)

  def up
    change_table :cold_networks, bulk: true do |t|
      t.change :id, :bigint, null: false, unsigned: true, auto_increment: true
      t.change :network_id, :bigint, unsigned: true
    end

    unless column_exists?(:cold_networks, :override)
      add_column :cold_networks, :override, :tinyint, null: false, default: 0
    end
  end

  def down
    change_table :cold_networks, bulk: true do |t|
      t.change :id, :integer, null: false, auto_increment: true
      t.change :network_id, :integer
    end

    if column_exists?(:cold_networks, :override)
      remove_column :cold_networks, :override
    end
  end
end
