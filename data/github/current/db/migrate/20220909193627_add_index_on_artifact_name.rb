# typed: true

class AddIndexOnArtifactName < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def change
    change_table :artifacts, bulk: true do |t|
      t.index [:repository_id, :name]
      t.remove_index :repository_id
    end
  end
end
