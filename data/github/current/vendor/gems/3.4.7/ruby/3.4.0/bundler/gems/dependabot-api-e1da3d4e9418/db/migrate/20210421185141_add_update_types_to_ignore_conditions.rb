# frozen_string_literal: true

class AddUpdateTypesToIgnoreConditions < ActiveRecord::Migration[6.0]
  def change
    change_column_null :ignore_conditions, :version_requirement, true
    add_column :ignore_conditions, :update_types, :json
  end
end
