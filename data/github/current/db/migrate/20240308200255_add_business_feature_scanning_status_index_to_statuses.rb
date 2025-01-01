class AddBusinessFeatureScanningStatusIndexToStatuses < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)
  def change
    add_index :repository_security_center_statuses, [:business_id, :feature_type, :scanning_status, :scanning_count, :repository_id],
      name: "index_business_id_feature_scanning_status_scanning_count_repo_id"
  end
end
