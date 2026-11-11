class DropOrcaPipelineRequests < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    drop_table :orca_pipeline_requests, if_exists: true
  end
end
