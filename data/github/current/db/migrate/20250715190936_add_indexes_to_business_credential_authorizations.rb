# typed: true

class AddIndexesToBusinessCredentialAuthorizations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :business_credential_authorizations, bulk: true do |t|
      # This unique index is necessary to prevent duplicate credentials for the same business
      # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
      t.index [:business_id, :fingerprint_sha256], unique: true, name: "index_bus_cred_auth_on_bus_id_and_fingerprint_sha256"
      # rubocop:enable GitHub/DoNotAddUniqueIndexToExistingColumn
      t.index [:business_id, :credential_id, :credential_type, :revoked_by_id], name: "index_bus_cred_auths_on_bus_and_cred_and_revoked_by"
      t.index [:business_id, :actor_id], name: "index_bus_credential_authorizations_on_bus_id_and_actor_id"
      t.index [:credential_id, :credential_type, :revoked_by_id], name: "index_on_credential_id_and_credential_type_and_revoked_by_id"
      t.index [:fingerprint_sha256, :credential_type], name: "index_bus_cred_auth_on_fingerprint_sha_256_and_cred_type"
      t.index [:actor_id, :actor_type], name: "index_bus_cred_auth_on_actor_id_and_actor_type"
      t.index [:business_id, :revoked_by_id, :is_application, :credential_type], name: "index_on_bus_id_revoked_by_id_is_application_cred_type"
    end
  end
end
