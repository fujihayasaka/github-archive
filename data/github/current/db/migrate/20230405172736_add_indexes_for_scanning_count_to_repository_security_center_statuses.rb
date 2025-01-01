# typed: true

class AddIndexesForScanningCountToRepositorySecurityCenterStatuses < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_security_center_statuses, bulk: true do |t|
      t.index [:organization_id, :feature_type, :scanning_status, :scanning_count, :repository_id], name: "index_org_id_feature_scanning_status_scanning_count_repo_id"
    end
  end
end
