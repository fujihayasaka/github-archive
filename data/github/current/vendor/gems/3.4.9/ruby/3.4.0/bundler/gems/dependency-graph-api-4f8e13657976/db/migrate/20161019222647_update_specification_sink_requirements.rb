class UpdateSpecificationSinkRequirements < ActiveRecord::Migration[5.0]
  def change
    remove_column :etl_dependency_spec_dependencies, :version, :string
    remove_column :etl_dependency_spec_dependencies, :operator, :string
    add_column :etl_dependency_spec_dependencies, :requirements, :string
  end
end
