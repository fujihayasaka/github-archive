# typed: true
class UpdateSettingIntTypesOnMergeQueue < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    change_table :merge_queues, bulk: true do |t|
      t.change :check_response_timeout_minutes, :smallint, unsigned: true, null: false, default: 60
      t.change :min_entries_to_merge_wait_minutes, :smallint, unsigned: true, null: false, default: 5
      t.change :max_entries_to_build, :tinyint, unsigned: true, null: false, default: 5
      t.change :max_entries_to_merge, :tinyint, unsigned: true, null: false, default: 5
      t.change :min_entries_to_merge, :tinyint, unsigned: true, null: false, default: 1
    end
  end
end
