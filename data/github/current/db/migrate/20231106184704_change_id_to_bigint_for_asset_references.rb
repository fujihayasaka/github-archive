# typed: true

class ChangeIdToBigintForAssetReferences < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Assets)

  def up
    change_table(:asset_references, bulk: true) do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :asset_id, :bigint, unsigned: true, null: false
      t.change :uploadable_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table(:asset_references, bulk: true) do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :asset_id, :int, null: false
      t.change :uploadable_id, :int, null: false
    end
  end
end
