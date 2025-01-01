# typed: true
class AddNewConfigurationSettingsToMergeQueues < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    change_table :merge_queues, bulk: true do |t|
      t.column :max_entries_to_build, :tinyint, null: false, default: 5
      t.column :check_response_timeout_minutes, :tinyint, null: false, default: 60
      t.column :merging_strategy, "ENUM('ALLGREEN', 'HEADGREEN')", null: false, default: "ALLGREEN"
      t.column :max_entries_to_merge, :tinyint, null: false, default: 5
      t.column :min_entries_to_merge, :tinyint, null: false, default: 1
      t.column :min_entries_to_merge_wait_minutes, :tinyint, null: false, default: 5
    end
  end
end
