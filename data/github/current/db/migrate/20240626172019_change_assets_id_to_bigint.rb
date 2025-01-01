# typed: true
# frozen_string_literal: true

class ChangeAssetsIdToBigint < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Assets)

  def up
    change_column :assets, :id, :bigint, unsigned: true, null: false, auto_increment: true
  end

  def down
    change_column :assets, :id, :int, null: false, auto_increment: true
  end
end
