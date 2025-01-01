class AddRepoFeatureSeverityIndexOnSecurityCenterAlertSeverities < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)
  def change
    change_table :security_center_alert_severities, bulk: true do |t|
      t.remove_index name: "index_security_center_alert_severities_repo_feature_severity"
      t.index [:repository_id, :feature_type, :severity, :alert_count], name: "idx_repo_feature_severity_alert_count"
    end
  end
end
