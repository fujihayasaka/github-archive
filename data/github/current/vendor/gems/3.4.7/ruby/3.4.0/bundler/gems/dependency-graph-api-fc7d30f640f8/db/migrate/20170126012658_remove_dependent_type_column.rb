class RemoveDependentTypeColumn < ActiveRecord::Migration[5.0]
  def change
    remove_column :dependency_specifications, :dependent_type, :string
  end
end
