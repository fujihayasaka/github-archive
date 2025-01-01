class IncreasePublicKeysFingerprintSize < ActiveRecord::Migration[7.1]
  def up
    change_table :public_keys, bulk: true do |t|
      t.change :fingerprint_sha256, "varbinary(96)"
      t.change :id, :bigint, unsigned: true
      t.change :user_id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
      t.change :creator_id, :bigint, unsigned: true
      t.change :verifier_id, :bigint, unsigned: true
      t.change :oauth_authorization_id, :bigint, unsigned: true
      t.change :oauth_application_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :public_keys, bulk: true do |t|
      t.change :fingerprint_sha256, "varbinary(64)"
      t.change :id, :int
      t.change :user_id, :int
      t.change :repository_id, :int
      t.change :creator_id, :int
      t.change :verifier_id, :int
      t.change :oauth_authorization_id, :int
      t.change :oauth_application_id, :int
    end
  end
end
