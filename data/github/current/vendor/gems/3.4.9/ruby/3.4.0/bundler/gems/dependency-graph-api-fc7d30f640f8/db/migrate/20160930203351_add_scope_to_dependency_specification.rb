class AddScopeToDependencySpecification < ActiveRecord::Migration[5.0]
  def change
    add_column :dependency_specifications, :scope, :integer, default: 0
  end
end
