# typed: true
# frozen_string_literal: true

class ChangeExternalIdentityRefreshTokensRefreshTokenColumnType < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table(:external_identity_refresh_tokens, bulk: true) do |t|
      t.change :refresh_token, :text
    end
  end

  def down
    change_table(:external_identity_refresh_tokens, bulk: true) do |t|
      t.change :refresh_token, :varbinary, limit: 2048
    end
  end
end
