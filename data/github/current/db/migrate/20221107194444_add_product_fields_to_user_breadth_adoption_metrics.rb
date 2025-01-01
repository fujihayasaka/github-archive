# typed: true

class AddProductFieldsToUserBreadthAdoptionMetrics < ActiveRecord::Migration[7.1]
  def change
    add_column :user_breadth_adoption_metrics, :category, :tinyint, default: 0, null: false
  end
end
