# typed: true
# frozen_string_literal: true

class ExternalIdentityRefreshTokenChangeNullConstraints < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    # change encrypted_refresh_token to allow nulls
    change_table(:external_identity_refresh_tokens, bulk: true) do |t|
      t.change :encrypted_refresh_token, "varbinary(8192)", null: true
    end
  end

  def down
    # change encrypted_refresh_token to not allow nulls
    change_table(:external_identity_refresh_tokens, bulk: true) do |t|
      t.change :refresh_token, :text, null: true
    end
  end
end
