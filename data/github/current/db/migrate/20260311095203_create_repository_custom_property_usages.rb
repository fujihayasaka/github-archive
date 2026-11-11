# typed: true
# frozen_string_literal: true

class CreateRepositoryCustomPropertyUsages < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)
  def change
    create_table :repository_custom_property_usages, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :definition_id, unsigned: true, null: false
      t.bigint :resource_id, unsigned: true, null: false
      t.integer :resource_type, null: false, unsigned: true, limit: 1

      t.index [:definition_id], name: "index_repository_custom_property_usages_on_definition_id"
      t.index [:resource_id, :resource_type], name: "index_repository_custom_property_usages_on_resource"
    end
  end
end
