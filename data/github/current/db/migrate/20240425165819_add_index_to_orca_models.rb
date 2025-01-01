class AddIndexToOrcaModels < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
    add_index :orca_models, :pipeline_id, unique: true
  end
end
