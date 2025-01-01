# typed: true
# frozen_string_literal: true

class UseBigintInImportItems < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_table :import_items, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, default: nil
      t.change :repository_id, :bigint, unsigned: true, default: nil
      t.change :user_id, :bigint, unsigned: true, default: nil
      t.change :model_id, :bigint, unsigned: true, default: nil
    end
  end

  def down
    change_table :import_items, bulk: true do |t|
      t.change :id, :int, default: nil
      t.change :repository_id, :int, default: nil
      t.change :user_id, :int, default: nil
      t.change :model_id, :int, default: nil
    end
  end
end
