# frozen_string_literal: true

class DropCodeshipColumns < ActiveRecord::Migration[6.0]
  def up
    drop_table :codeship_projects
    drop_table :codeship_accounts
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "CodeShip tables have been deleted"
  end
end
