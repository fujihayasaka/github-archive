# typed: true
# frozen_string_literal: true

class ChangeTablePushesToBigint < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def up
    change_table :pushes, bulk: true do |t|
      t.change :repository_id, :bigint, unsigned: true
      t.change :pusher_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :pushes, bulk: true do |t|
      t.change :repository_id, :int
      t.change :pusher_id, :int
    end
  end
end
