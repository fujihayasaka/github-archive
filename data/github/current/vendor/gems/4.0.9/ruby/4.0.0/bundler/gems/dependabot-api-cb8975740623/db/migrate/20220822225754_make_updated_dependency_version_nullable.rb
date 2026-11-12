# frozen_string_literal: true

class MakeUpdatedDependencyVersionNullable < ActiveRecord::Migration[6.1]
  def change
    change_column_null :updated_dependencies, :version, true
  end
end
