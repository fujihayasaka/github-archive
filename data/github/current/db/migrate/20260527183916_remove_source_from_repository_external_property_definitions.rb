# typed: true
# frozen_string_literal: true

class RemoveSourceFromRepositoryExternalPropertyDefinitions < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)
  def up
    change_table :repository_external_property_definitions, bulk: true do |t|
      t.remove :source_id
      t.remove :source_type
    end
  end

  def down
    change_table :repository_external_property_definitions, bulk: true do |t|
      t.integer :source_type, null: true, default: 0, unsigned: true, limit: 1
      t.bigint :source_id, null: true, unsigned: true
    end
  end
end
