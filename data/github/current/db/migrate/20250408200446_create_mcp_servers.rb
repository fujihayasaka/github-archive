# typed: true
# frozen_string_literal: true

class CreateMcpServers < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    # Represents a remote MCP Server that a user can configure to use with Copilot.
    create_table :mcp_servers, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :name, null: false
      t.text :url, null: false
      t.string :oauth_client_id, null: false
      t.text :oauth_client_secret, null: false
      t.timestamps
    end
  end
end
