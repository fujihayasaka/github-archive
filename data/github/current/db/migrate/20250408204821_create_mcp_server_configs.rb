# typed: true
# frozen_string_literal: true

class CreateMcpServerConfigs < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    # Represents a remote MCP server that a user has enabled and authorized to use with Copilot.
    create_table :mcp_server_configs, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, null: false
      t.bigint :mcp_server_id, unsigned: true, null: false
      t.text :code_verifier, null: true
      t.text :access_token, null: true
      t.text :refresh_token, null: true
      t.datetime :access_token_expires_at, null: true, precision: 6
      t.timestamps

      t.index [:user_id, :mcp_server_id], unique: true, name: "index_copilot_external_tokens_on_user_id_and_mcp_server_id"
    end
  end
end
