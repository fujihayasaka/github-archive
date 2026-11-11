class AddArtifactsIndexExpirationEmittedExpiredAt < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def change
    change_table :artifacts, bulk: true do |t|
      t.index [:expiration_emitted, :expires_at], name: "index_artifacts_on_expiration_emitted_and_expires_at"
      t.remove_index [:created_at, :expiration_emitted], name: "index_artifacts_on_created_at_and_expiration_emitted"
    end
  end
end
