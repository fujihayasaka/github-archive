# typed: true
# frozen_string_literal: true

class AddBusinessIdToExternalGroupTeams < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Usersd)

  def up
    change_table :external_group_teams, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :external_group_id, :bigint, unsigned: true, null: false
      t.change :team_id, :bigint, unsigned: true, null: false
      t.column :business_id, :bigint, unsigned: true, null: true
      t.index :business_id, name: "index_external_group_teams_on_business_id"
    end
  end

  def down
    change_table :external_group_teams, bulk: true do |t|
      t.remove_index name: "index_external_group_teams_on_business_id"
      t.remove :business_id
      t.change :id, :integer, null: false, auto_increment: true
      t.change :external_group_id, :integer, null: false
      t.change :team_id, :integer, null: false
    end
  end
end
