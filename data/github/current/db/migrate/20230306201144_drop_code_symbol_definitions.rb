# typed: true

class DropCodeSymbolDefinitions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    drop_table :code_symbol_definitions, if_exists: true
  end
end
