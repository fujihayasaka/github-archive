# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class AddSyncStatusToExternalGroupTeams < ActiveRecord::Migration[7.1]
  def up
    change_table :external_group_teams, bulk: true do |t|
      t.column :sync_status, :integer, null: false, default: 1
      t.index [:external_group_id, :sync_status], name: "index_external_group_teams_on_external_group_id_and_sync_status"
    end
  end

  def down
    change_table :external_group_teams, bulk: true do |t|
      t.remove :sync_status
      t.remove_index [:external_group_id, :sync_status], name: "index_external_group_teams_on_external_group_id_and_sync_status"
    end
  end
end
