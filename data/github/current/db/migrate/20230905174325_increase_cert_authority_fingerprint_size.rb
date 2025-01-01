class IncreaseCertAuthorityFingerprintSize < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table :ssh_certificate_authorities, bulk: true do |t|
      t.change :fingerprint, "varbinary(64)"
      t.change :id, :bigint, unsigned: true
      t.change :owner_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :ssh_certificate_authorities, bulk: true do |t|
      t.change :fingerprint, "varbinary(32)"
      t.change :id, :int
      t.change :owner_id, :int
    end
  end
end
