# typed: true
# frozen_string_literal: true

class CreateRepositoryExternalPropertyNamespaces < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)
  def change
    create_table :repository_external_property_namespaces, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.integer :source_type, null: false, default: 0, unsigned: true, limit: 1
      t.bigint :source_id, null: false, unsigned: true
      t.bigint :integration_id, null: false, unsigned: true
      t.string :display_name, null: false, limit: 15

      t.index [:source_id, :source_type, :integration_id], unique: true, name: "index_on_source_id_source_type_and_integration_id"
      t.index [:source_id, :source_type, :display_name], unique: true, name: "index_on_source_id_source_type_and_display_name"
    end
  end
end
