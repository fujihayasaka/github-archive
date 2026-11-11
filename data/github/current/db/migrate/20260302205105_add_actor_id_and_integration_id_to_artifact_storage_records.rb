# typed: true
# frozen_string_literal: true

class AddActorIdAndIntegrationIdToArtifactStorageRecords < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    change_table :artifact_storage_records, bulk: true do |t|
      t.column :actor_id, :bigint, unsigned: true, null: true
      t.column :integration_id, :bigint, unsigned: true, null: true
    end
  end
end
