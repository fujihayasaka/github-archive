# typed: true

class DropRepositoryCodeSymbolIndices < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    drop_table :repository_code_symbol_indices, if_exists: true
  end
end
