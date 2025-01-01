# typed: true
class AddArtifactsExpirationEmittedColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def change
    change_table :artifacts, bulk: true do |t|
      t.column :expiration_emitted, :boolean, default: false, null: false
      t.index [:created_at, :expiration_emitted]
      t.index [:expires_at, :expiration_emitted]
    end
  end
end
