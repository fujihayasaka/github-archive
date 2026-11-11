# typed: true

class SecretScanningEnhancedMetadataSecurityConfigs < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::RepositoriesNotify

  def change
    add_column :security_configurations, :secret_scanning_extended_metadata, :integer,
      after: :secret_scanning_delegated_bypass, limit: 1, null: true
  end
end
