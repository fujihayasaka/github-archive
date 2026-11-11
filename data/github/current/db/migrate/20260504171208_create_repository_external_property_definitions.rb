# typed: true
# frozen_string_literal: true

class CreateRepositoryExternalPropertyDefinitions < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)
  def change
    create_table :repository_external_property_definitions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :property_name, null: false, limit: 75
      t.integer :source_type, null: false, default: 0, unsigned: true, limit: 1
      t.bigint :source_id, null: false, unsigned: true
      t.bigint :namespace_id, null: false, unsigned: true

      t.index [:source_id, :source_type, :namespace_id, :property_name], unique: true, name: "index_repo_ext_property_defs_on_source_namespace_and_name"
    end
  end
end
