# typed: true

class AddOrganizationCredentialAuthorizationsJti < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :organization_credential_authorizations, bulk: true do |t|
      t.binary :jti, null: true, limit: 16, after: :actor_type
      t.index [:jti, :revoked_by_id]
    end
  end
end
