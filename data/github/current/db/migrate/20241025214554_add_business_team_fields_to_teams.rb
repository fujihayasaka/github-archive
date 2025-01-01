# typed: true
# frozen_string_literal: true

class AddBusinessTeamFieldsToTeams < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :teams, bulk: true do |t|
      t.column :business_id, :bigint, unsigned: true, null: true
      t.column :organization_selection_type, :tinyint, unsigned: true, null: false, default: 0
      t.change :organization_id, :bigint, unsigned: true, null: true
      t.column :type, :string, null: false, default: "Team", limit: 12
      t.index :business_id
      t.index :type
    end
  end

  def down
    remove_column :teams, :business_id, :bigint
    remove_column :teams, :organization_selection_type, :tinyint
    change_column :teams, :organization_id, :bigint, unsigned: true, null: false
    remove_column :teams, :type, :string
  end
end
