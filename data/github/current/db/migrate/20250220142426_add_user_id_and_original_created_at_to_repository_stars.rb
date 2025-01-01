# typed: true

class AddUserIdAndOriginalCreatedAtToRepositoryStars < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::Restorables

  def up
    change_table :restorable_repository_stars, bulk: true do |t|
      t.bigint :user_id, unsigned: true
      t.datetime :original_created_at, precision: 6

      # Upgrade integer primary and foreign key columns to BIGINT
      t.change :id, :bigint, unsigned: true
      t.change :restorable_id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :restorable_repository_stars, bulk: true do |t|
      t.remove :user_id
      t.remove :original_created_at

      t.change :id, :int, unsigned: false
      t.change :restorable_id, :int, unsigned: false
      t.change :repository_id, :int, unsigned: false
    end
  end
end
