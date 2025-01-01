class DropSecurityOverviewRiskLevel < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_security_center_configs, bulk: true do |t|
      t.remove :risk_level
      t.remove_index name: "index_on_organization_id_archived_risk_level_repository_id"
    end
  end
end
