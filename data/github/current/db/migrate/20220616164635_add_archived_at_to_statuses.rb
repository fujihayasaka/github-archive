# typed: true

class AddArchivedAtToStatuses < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    change_table :statuses, bulk: true do |t|
      t.change :repository_id, :bigint, unsigned: true
      t.change :creator_id, :bigint, unsigned: true
      t.change :pull_request_id, :bigint, unsigned: true
      t.change :oauth_application_id, :bigint, unsigned: true
      t.change :performed_by_integration_id, :bigint, unsigned: true

      t.datetime :archived_at, precision: 6, null: true, default: nil
      t.virtual :is_archived, type: :tinyint, as: "archived_at IS NOT NULL"
      t.index [:archived_at], name: "index_statuses_on_archived_at"
      t.index [:repository_id, :is_archived, :updated_at], name: "index_statuses_on_repository_id_is_archived_updated_at"
      t.index [:is_archived, :updated_at], name: "index_statuses_on_is_archived_updated_at"
    end
  end

  def down
    change_table :statuses, bulk: true do |t|
      t.change :repository_id, "int(11)", unsigned: true
      t.change :creator_id, "int(11)", unsigned: true
      t.change :pull_request_id, "int(11)", unsigned: true
      t.change :oauth_application_id, "int(11)", unsigned: false
      t.change :performed_by_integration_id, "int(11)", unsigned: true

      t.remove :archived_at, precision: 6, null: true, default: nil
      t.remove :is_archived, type: :tinyint, as: "archived_at IS NOT NULL"
      t.remove_index [:archived_at], name: "index_statuses_on_archived_at"
      t.remove_index [:repository_id, :is_archived, :updated_at], name: "index_statuses_on_repository_id_is_archived_updated_at"
      t.remove_index [:is_archived, :updated_at], name: "index_statuses_on_is_archived_updated_at"
    end
  end
end
