# typed: true
# frozen_string_literal: true

class AddOIDCCopilotExtensions < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :integration_agents, bulk: true do |t|
      t.column :token_exchange_enabled, :boolean, default: false, null: false
      t.text :token_exchange_url
      t.text :third_party_token_header_key
      t.text :third_party_token_header_value
    end
  end
end
