class ArtifactsIdKeyspaceIdxIdBigint < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    change_table :artifacts_id_keyspace_idx, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :artifacts_id_keyspace_idx, bulk: true do |t|
      t.change :id, :int, unsigned: false, null: false
    end
  end
end
