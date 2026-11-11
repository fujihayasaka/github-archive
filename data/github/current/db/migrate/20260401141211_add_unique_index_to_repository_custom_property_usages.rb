# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class AddUniqueIndexToRepositoryCustomPropertyUsages < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table :repository_custom_property_usages, bulk: true do |t|
      t.remove_index [:resource_id, :resource_type], name: "index_repository_custom_property_usages_on_resource"

      t.index [:resource_id, :resource_type, :definition_id], unique: true, name: "idx_repo_custom_property_usages_on_resource_id_type_and_def_id"
    end
  end
end
