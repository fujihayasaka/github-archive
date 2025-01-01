class DeleteOauthLogs < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    drop_table :oauth_logs
  end
end
