# typed: true
# frozen_string_literal: true

class DropEncryptedRefreshToken < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table(:external_identity_refresh_tokens, bulk: true) do |t|
      t.remove :encrypted_refresh_token
      t.change :refresh_token, :text, null: false
    end
  end

  def down
    change_table(:external_identity_refresh_tokens, bulk: true) do |t|
      t.change :refresh_token, :text, null: true
      t.column :encrypted_refresh_token, "varbinary(8192)", null: true
    end
  end
end
