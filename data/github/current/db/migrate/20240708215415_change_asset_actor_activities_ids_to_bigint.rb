# typed: true
# frozen_string_literal: true

class ChangeAssetActorActivitiesIdsToBigint < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Assets)

  def up
    change_table(:asset_actor_activities, bulk: true) do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :owner_id, :bigint, unsigned: true, null: false
      t.change :actor_id, :bigint, unsigned: true, null: false
      t.change :repository_id, :bigint, unsigned: true, null: false, default: 0
      t.change :key_id, :bigint, unsigned: true, null: false, default: 0
    end
  end

  def down
    change_table(:asset_actor_activities, bulk: true) do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :owner_id, :int, null: false
      t.change :actor_id, :int, null: false
      t.change :repository_id, :int, null: false, default: 0
      t.change :key_id, :int, null: false, default: 0
    end
  end
end
