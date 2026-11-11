# typed: true
# frozen_string_literal: true

class ChangeAvatarsIdsToBigint < ActiveRecord::Migration[8.0] # rubocop:disable GitHub/ConnectionClassPresentInMigration
  def up
    change_table :avatars, bulk: true do |t| # rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :asset_id, :bigint, unsigned: true
      t.change :owner_id, :bigint, unsigned: true, null: false
      t.change :uploader_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :avatars, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :asset_id, :int
      t.change :owner_id, :int, null: false
      t.change :uploader_id, :int
    end
  end
end
