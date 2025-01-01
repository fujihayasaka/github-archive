class DropUnusedArtifactIndex < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def change
    change_table :artifacts, bulk: true do |t|
      t.remove_index [:expires_at, :expiration_emitted], name: "index_artifacts_on_expires_at_and_expiration_emitted"
    end
  end
end
