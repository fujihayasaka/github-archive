# typed: true

class AddIndexesForStatsToRepositorySecurityCenterStatuses < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_security_center_statuses, bulk: true do |t|
      t.index [:organization_id, :feature_type, :scanning_status, :repository_id], name: "index_org_id_feature_scanning_status_repo_id"
      t.index [:organization_id, :repository_id, :feature_type, :scanning_status], name: "index_org_id_repo_id_feature_type_scanning_status"
    end
  end

end
