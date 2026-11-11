# frozen_string_literal: true

class DropDependenciesTable < ActiveRecord::Migration[6.0]
  def up
    drop_table :dependencies
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Dependencies table has been deleted"
  end
end
