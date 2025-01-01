# typed: true

class AddOauthRedirectUriToMcpServers < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  # rubocop:disable GitHub/OneTablePerMigration, GitHub/ArchivedTable
  def up
    change_table :mcp_servers, bulk: true do |t|
      t.text :oauth_redirect_uri, null: true
    end

    remove_index :mcp_servers, name: :index_mcp_servers_on_url_and_oauth_client_id

    # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
    add_index :mcp_servers, "url(255), oauth_redirect_uri(255)",
              unique: true,
              name: :index_mcp_servers_on_url_and_oauth_redirect_uri
    # rubocop:enable GitHub/DoNotAddUniqueIndexToExistingColumn
  end

  def down
    remove_index :mcp_servers, name: :index_mcp_servers_on_url_and_oauth_redirect_uri

    add_index :mcp_servers, "url(255), oauth_client_id",
              unique: true,
              name: :index_mcp_servers_on_url_and_oauth_client_id

    change_table :mcp_servers, bulk: true do |t|
      t.remove :oauth_redirect_uri
    end
  end
  # rubocop:enable GitHub/OneTablePerMigration, GitHub/ArchivedTable
end
