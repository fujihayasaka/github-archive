class DropDependsOnId < ActiveRecord::Migration[5.0]
  def up
    if column_exists?(:dependency_specifications, :depends_on_id)
      remove_column :dependency_specifications, :depends_on_id, :integer
    end
  end

  def down
    unless column_exists?(:dependency_specifications, :depends_on_id)
      add_column :dependency_specifications, :depends_on_id, :integer
    end
  end
end
