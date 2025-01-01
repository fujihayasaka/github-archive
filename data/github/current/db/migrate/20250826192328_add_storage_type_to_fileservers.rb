# typed: true
# frozen_string_literal: true

class AddStorageTypeToFileservers < ActiveRecord::Migration[8.1]

  self.use_connection_class(ApplicationRecord::Domain::Spokes)

  def up
    change_table :fileservers, bulk: true do |t|
      t.change :id, :bigint, null: false, auto_increment: true
      unless column_exists?(:fileservers, :storage_type)
        t.column :storage_type, :tinyint, null: false, default: 0
      end
    end
  end

  def down
    change_table :fileservers, bulk: true do |t|
      t.change :id, :integer, null: false, auto_increment: true
      t.remove :storage_type if column_exists?(:fileservers, :storage_type)
    end
  end
end
