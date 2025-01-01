class AddEtlSourceTimestamps < ActiveRecord::Migration[5.0]
  def change
    add_column :etl_output_package_versions, :published_at, :timestamp
    add_column :etl_dependency_specs, :pushed_at, :timestamp
  end
end
