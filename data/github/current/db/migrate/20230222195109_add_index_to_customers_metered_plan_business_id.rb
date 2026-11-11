# typed: true

class AddIndexToCustomersMeteredPlanBusinessId < ActiveRecord::Migration[7.1]
  def up
    unless index_exists?(:customers, [:metered_plan])
      add_index :customers, [:metered_plan]
    end
  end

  def down
    if index_exists?(:customers, [:metered_plan])
      remove_index :customers, [:metered_plan]
    end
  end
end
