class AddPipelineIdToConsumerVersion < ActiveRecord::Migration[5.0]
  def change
    add_column :consumer_versions, :specification_pipeline_id, :integer, index: true
  end
end
