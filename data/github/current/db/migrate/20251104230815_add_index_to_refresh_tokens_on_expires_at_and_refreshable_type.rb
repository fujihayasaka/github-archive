# typed: true
# frozen_string_literal: true

class AddIndexToRefreshTokensOnExpiresAtAndRefreshableType < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsCollab)

  def change
    change_table :refresh_tokens, bulk: true do |t|
      t.index [:expires_at, :refreshable_type], name: "index_refresh_tokens_on_expires_at_and_refreshable_type"
    end
  end
end
