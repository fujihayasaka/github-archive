class RemoveUnusedColumns < ActiveRecord::Migration[5.0]
  def change
    remove_column :package_versions, :package_pipeline_id, :integer
    remove_column :package_versions, :specification_pipeline_id, :integer

    remove_column :packages, :package_pipeline_id, :integer
    remove_column :packages, :specification_pipeline_id, :integer

    remove_column :consumer_versions, :specification_pipeline_id, :integer
  end
end
