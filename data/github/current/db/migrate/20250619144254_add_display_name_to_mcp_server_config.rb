# typed: true
# frozen_string_literal: true

class AddDisplayNameToMcpServerConfig < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    add_column :mcp_server_configs, :display_name, :string
  end
end
