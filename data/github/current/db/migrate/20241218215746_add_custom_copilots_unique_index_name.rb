# typed: true

class AddCustomCopilotsUniqueIndexName < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_index :custom_copilots, [:owner_id, :owner_type, :name], unique: true, name: "index_custom_copilots_on_owner_id_and_owner_type_and_name" # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
  end
end
