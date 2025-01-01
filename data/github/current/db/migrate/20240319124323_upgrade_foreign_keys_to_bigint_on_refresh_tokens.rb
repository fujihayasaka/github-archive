# typed: true
# frozen_string_literal: true

class UpgradeForeignKeysToBigintOnRefreshTokens < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsCollab)

  def up
    change_table :refresh_tokens, bulk: true do |t|
      t.change :refreshable_id, :bigint, null: false
    end
  end

  def down
    change_table :refresh_tokens, bulk: true do |t|
      t.change :refreshable_id, :int, null: false
    end
  end
end
