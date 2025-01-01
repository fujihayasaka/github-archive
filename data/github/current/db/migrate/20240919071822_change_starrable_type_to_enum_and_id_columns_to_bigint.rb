# typed: true
# frozen_string_literal: true

class ChangeStarrableTypeToEnumAndIdColumnsToBigint < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def up
    change_table(:stars, bulk: true) do |t|
      t.change :id, :bigint, unsigned: false, null: false
      t.change :user_id, :bigint, unsigned: false, null: false
      t.change :starrable_id, :bigint, unsigned: false, null: false
      t.change :starrable_type, "enum('Repository', 'Topic')", null: true, default: nil
    end
  end

  def down
    change_table(:stars, bulk: :true) do |t|
      t.change :id, :int, null: false
      t.change :user_id, :int, null: false
      t.change :starrable_id, :int, null: false
      t.change :starrable_type, "varchar(30)", null: true, default: nil
    end
  end
end
