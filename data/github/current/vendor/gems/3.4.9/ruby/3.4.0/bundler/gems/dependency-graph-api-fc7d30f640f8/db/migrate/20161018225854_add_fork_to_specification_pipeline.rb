class AddForkToSpecificationPipeline < ActiveRecord::Migration[5.0]
  def change
    add_column :etl_dependency_specs, :fork, :boolean, default: false
  end
end
