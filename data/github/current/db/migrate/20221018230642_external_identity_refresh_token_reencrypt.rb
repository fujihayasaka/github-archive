# typed: false

class ExternalIdentityRefreshTokenReencrypt < ActiveRecord::Migration[7.1]
  def self.up
    # Change from VARBINARY(2048) to VARBINARY(8192) to ensure
    # there is enough space for the ciphertext + metadata
    change_column :external_identity_refresh_tokens, :encrypted_refresh_token, "varbinary(8192)"
  end

  def self.down
    # Keep the column type as VARBINARY(8192) since the values inserted
    # since the update might be too large to fit into their
    # old size
    change_column :external_identity_refresh_tokens, :encrypted_refresh_token, "varbinary(8192)"
  end
end
