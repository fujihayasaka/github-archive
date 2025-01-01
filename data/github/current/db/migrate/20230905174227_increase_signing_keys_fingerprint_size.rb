class IncreaseSigningKeysFingerprintSize < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table :git_signing_ssh_public_keys, bulk: true do |t|
      t.change :fingerprint_sha256, "varbinary(96)"
    end
  end

  def down
    change_table :git_signing_ssh_public_keys, bulk: true do |t|
      t.change :fingerprint_sha256, "varbinary(64)"
    end
  end
end
