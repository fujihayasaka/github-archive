class AddLastIssuedAtToOauthAccess < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    add_column :oauth_accesses, :last_issued_at, :datetime, precision: 6, null: true
  end
end
