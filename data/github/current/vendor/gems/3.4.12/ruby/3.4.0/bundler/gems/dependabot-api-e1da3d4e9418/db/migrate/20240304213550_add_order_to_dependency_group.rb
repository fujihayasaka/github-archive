# frozen_string_literal: true

class AddOrderToDependencyGroup < ActiveRecord::Migration[7.0]
  def change
    add_column :dependency_groups, :sort_order, :integer
  end
end
