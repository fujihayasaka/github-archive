# typed: true
# frozen_string_literal: true

class ConfigurationEntriesIdsToBigint < ActiveRecord::Migration[7.1]

  self.use_connection_class(ApplicationRecord::Domain::ConfigurationEntries)
  def up
    change_table :configuration_entries, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :target_id, :bigint, unsigned: true
      t.change :updater_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :configuration_entries, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :target_id, :int, null: false
      t.change :updater_id, :int, null: false
    end
  end
end
