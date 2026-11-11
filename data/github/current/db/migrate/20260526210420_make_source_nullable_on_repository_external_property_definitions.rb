# typed: true
# frozen_string_literal: true

class MakeSourceNullableOnRepositoryExternalPropertyDefinitions < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table :repository_external_property_definitions, bulk: true do |t|
      t.change_null :source_id, true
      t.change_null :source_type, true

      t.remove_index name: "index_repo_ext_property_defs_on_source_namespace_and_name"

      t.index [:namespace_id, :property_name], # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
        unique: true,
        name: "index_on_namespace_id_and_property_name"
    end
  end
end
