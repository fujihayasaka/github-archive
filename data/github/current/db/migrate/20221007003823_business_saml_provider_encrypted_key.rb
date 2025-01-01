# typed: false

class BusinessSamlProviderEncryptedKey < ActiveRecord::Migration[7.1]
  def self.up
    # Change from VARBINARY(2048) to VARBINARY(4096) to ensure
    # there is enough space for the ciphertext + metadata
    change_column :business_saml_provider_test_settings, :encrypted_key, "varbinary(4096)"
    change_column :business_saml_providers, :encrypted_key, "varbinary(4096)"
  end

  def self.down
    # Keep the column type as VARBINARY(4096) since the values inserted
    # since the update might be too large to fit into their
    # old size
    change_column :business_saml_provider_test_settings, :encrypted_key, "varbinary(4096)"
    change_column :business_saml_providers, :encrypted_key, :varbinary, "varbinary(4096)"
  end
end
