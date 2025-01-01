# typed: false
# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
class IncreaseTeamSyncBusinessTenantEncryptedSswsTokenSize < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Notify)
  def self.up
    # Change from VARBINARY(1024) to VARBINARY(2048) to ensure
    # there is enough space for the ciphertext + metadata
    change_column :team_sync_business_tenants, :encrypted_ssws_token, "varbinary(2048)"
  end

  def self.down
    # Keep the column type as VARBINARY(2048) since the values inserted
    # since the update might be too large to fit into their
    # old size
    change_column :team_sync_business_tenants, :encrypted_ssws_token, "varbinary(2048)"
  end
end
