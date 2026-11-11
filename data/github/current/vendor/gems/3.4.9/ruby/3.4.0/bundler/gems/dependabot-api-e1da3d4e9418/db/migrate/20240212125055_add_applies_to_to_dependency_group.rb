# frozen_string_literal: true

class AddAppliesToToDependencyGroup < ActiveRecord::Migration[7.0]
  def change
    add_column :dependency_groups, :applies_to, :string
  end
end
