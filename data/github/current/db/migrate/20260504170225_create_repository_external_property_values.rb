# typed: true
# frozen_string_literal: true

class CreateRepositoryExternalPropertyValues < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)
  def change
    create_table :repository_external_property_values, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :target_id, null: false, unsigned: true
      t.bigint :definition_id, null: false, unsigned: true
      t.string :value, null: false, limit: 200

      t.index [:definition_id, :value], name: "index_repo_ext_property_values_on_definition_and_value"
      t.index [:target_id, :definition_id], name: "index_repo_ext_property_values_on_target_and_definition"
    end
  end
end
