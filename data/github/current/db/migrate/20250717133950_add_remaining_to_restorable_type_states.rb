# typed: true

class AddRemainingToRestorableTypeStates < ActiveRecord::Migration[8.1]
  use_connection_class(ApplicationRecord::Domain::Restorables)

  def up
    change_table(:restorable_type_states, bulk: true) do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :restorable_id, :bigint, unsigned: true, default: nil, null: true

      t.column :remaining, :integer, default: nil, null: true
    end
  end

  def down
    change_table(:restorable_type_states, bulk: true) do |t|
      t.remove :remaining

      t.change :id, :integer, null: false, auto_increment: true
      t.change :restorable_id, :integer, default: nil, null: true
    end
  end
end
