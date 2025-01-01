# typed: true

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class AddEmbeddingsIndexingOnlyFieldToCopilotIndexedRepositories < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def up
    change_table :copilot_indexed_repositories, bulk: true do |t|
      t.column :embeddings_indexing_only, :boolean, null: false, default: false
    end
  end

  def down
    change_table :copilot_indexed_repositories, bulk: true do |t|
      t.remove :embeddings_indexing_only
    end
  end
end
