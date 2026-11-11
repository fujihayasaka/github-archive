# rubocop:disable GitHub/AvoidTypeBeforeId
class AddSecurityCenterBusinessIdIndexes < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_security_center_configs, bulk: true do |t|
      t.index [:business_id, :archived, :owner_id, :owner_type, :repository_id], name: "idx_repo_security_center_configs_business_id_owner_id_then_type"
      t.index [:business_id, :archived, :owner_type, :owner_id, :repository_id], name: "idx_repo_security_center_configs_business_id_owner_type_then_id"
    end
  end
end
