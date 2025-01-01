class AddSecurityConfigurationIdToBypassReviewers < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table(:secret_scanning_bypass_reviewers, bulk: true) do |t|
      t.column :security_configuration_id, :bigint, unsigned: true, null: true, comment: "If this bypass reviewer is for a security configuration, this is its ID"
      t.index [:security_configuration_id], name: "index_security_configuration_id", comment: "Supports lookups by security_configuration_id"
    end
  end

  def down
    change_table(:secret_scanning_bypass_reviewers, bulk: true) do |t|
      t.remove :security_configuration_id
      t.remove_index name: "index_security_configuration_id"
    end
  end
end
