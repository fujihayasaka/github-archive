class AddPackageToSpecificationSink < ActiveRecord::Migration[5.0]
  def change
    add_column :etl_dependency_specs, :package, :boolean
  end
end
