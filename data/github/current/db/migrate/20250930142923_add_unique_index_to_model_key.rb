# typed: true

class AddUniqueIndexToModelKey < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def up
    change_table :model_registry_cache, bulk: true do |t|
      t.remove_index :model_key
      t.remove :model_key
      t.string :model_key, null: false, limit: 30
      # There is no data in this table, so we can safely add a unique index
      # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
      t.index :model_key, unique: true
    end
  end

  def down
    change_table :model_registry_cache, bulk: true do |t|
      t.remove_index :model_key
      t.remove :model_key
      t.string :model_key, null: false  # Original column definition
      t.index :model_key   # Non-unique index
    end
  end
end
