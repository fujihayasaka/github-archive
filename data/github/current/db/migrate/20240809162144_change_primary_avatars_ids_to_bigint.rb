# typed: true
# frozen_string_literal: true

class ChangePrimaryAvatarsIdsToBigint < ActiveRecord::Migration[8.0] # rubocop:disable GitHub/ConnectionClassPresentInMigration
  def up
    change_table :primary_avatars, bulk: true do |t| # rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :avatar_id, :bigint, unsigned: true, null: false
      t.change :owner_id, :bigint, unsigned: true, null: false
      t.change :updater_id, :bigint, unsigned: true
      t.change :previous_avatar_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :primary_avatars, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :avatar_id, :int, null: false
      t.change :owner_id, :int, null: false
      t.change :updater_id, :int
      t.change :previous_avatar_id, :int
    end
  end
end
