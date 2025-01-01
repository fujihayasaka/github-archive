# typed: true
# frozen_string_literal: true

class ChangeAttachmentIdsToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::AssetObjects)

  def up
    change_table :attachments, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :attacher_id, :bigint, unsigned: true, null: false
      t.change :asset_id, :bigint, unsigned: true, null: false
      t.change :attachable_id, :bigint, unsigned: true, null: false
      t.change :entity_id, :bigint, unsigned: true, default: nil
    end
  end

  def down
    change_table :attachments, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :attacher_id, :int, null: false
      t.change :asset_id, :int, null: false
      t.change :attachable_id, :int, null: false
      t.change :entity_id, :int, default: nil
    end
  end
end
