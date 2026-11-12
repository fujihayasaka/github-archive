# frozen_string_literal: true

class AddDirectoryToUpdatedDependencies < ActiveRecord::Migration[7.0]
  def change
    add_column :updated_dependencies, :directory, :string
  end
end
