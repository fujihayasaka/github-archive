# frozen_string_literal: true

class AddRemovedToUpdatedDependency < ActiveRecord::Migration[6.1]
  def change
    add_column :updated_dependencies, :removed, :boolean, default: false, null: false
  end
end
