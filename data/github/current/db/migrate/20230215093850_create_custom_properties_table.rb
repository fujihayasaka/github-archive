# typed: true
# frozen_string_literal: true

class CreateCustomPropertiesTable < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    create_table :custom_properties, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint    :entity_id, unsigned: true, null: false, index: { unique: true }
      t.json      :properties, null: false
    end
  end
end
