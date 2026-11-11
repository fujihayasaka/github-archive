# typed: true
# frozen_string_literal: true

class RepositoryCustomPropertyValuesIncreaseValueLength < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_table :custom_property_values, bulk: true do |t|
      t.change :value, :string, null: false, limit: 200
    end
  end

  def down
    change_table :custom_property_values, bulk: true do |t|
      t.change :value, :string, null: false, limit: 75
    end
  end
end
