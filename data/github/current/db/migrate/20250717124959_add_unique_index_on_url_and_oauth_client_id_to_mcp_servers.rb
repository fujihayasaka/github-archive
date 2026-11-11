# typed: true
# frozen_string_literal: true

class AddUniqueIndexOnUrlAndOauthClientIdToMcpServers < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
    add_index :mcp_servers, "url(255), oauth_client_id",
              unique: true,
              name: :index_mcp_servers_on_url_and_oauth_client_id
    # rubocop:enable GitHub/DoNotAddUniqueIndexToExistingColumn
  end
end
