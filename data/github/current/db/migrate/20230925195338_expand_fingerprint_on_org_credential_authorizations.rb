class ExpandFingerprintOnOrgCredentialAuthorizations < ActiveRecord::Migration[7.1]
  def up
    change_table :organization_credential_authorizations, bulk: true do |t|
      t.change :fingerprint_sha256, "varbinary(96)"
    end
  end

  def down
    change_table :organization_credential_authorizations, bulk: true do |t|
      t.change :fingerprint_sha256, "varbinary(64)"
    end
  end
end
