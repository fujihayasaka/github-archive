class ChangeDependencyScopeDefault < ActiveRecord::Migration[5.0]
  def change
    change_column_default(:dependency_specifications, :scope, 1)
  end
end
