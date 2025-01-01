# typed: true

class DropSoaSecretScanningTokenRevisions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::SecurityOverviewAnalytics)

  def change
    drop_table :soa_secret_scanning_token_revisions, if_exists: true
  end
end
