# typed: true
# frozen_string_literal: true

class DropCustomPropertiesTable < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    drop_table :custom_properties, if_exists: true do |t|
      t.bigint :entity_id, unsigned: true, null: false, index: { unique: true }
      t.json :properties, null: false
    end
  end
end
