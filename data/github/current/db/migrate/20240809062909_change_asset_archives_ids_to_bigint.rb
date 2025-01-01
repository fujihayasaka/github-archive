# typed: true
# frozen_string_literal: true

class ChangeAssetArchivesIdsToBigint < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Assets)

  def up
    change_table(:asset_archives, bulk: true) do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :asset_id, :bigint, unsigned: true, null: true, default: nil
    end
  end

  def down
    change_table(:asset_archives, bulk: true) do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :asset_id, :int, null: true, default: nil
    end
  end
end
