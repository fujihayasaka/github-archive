# typed: true

class AddingRepositoryIdToExemptionRequestIndices < ActiveRecord::Migration[8.1]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)
  def change
    change_table :exemption_requests, bulk: true do |t|

      t.remove_index column: [:resource_owner_id, :resource_owner_type, :expires_at], name: "index_exemption_requests_resource_owner"
      t.remove_index column: [:request_type, :resource_identifier, :expires_at], name: "index_exemption_requests_resource_identifier"

      t.index [:resource_owner_id, :resource_owner_type, :expires_at, :repository_id], name: "index_exemption_requests_resource_owner_and_repo"
      t.index [:request_type, :resource_identifier, :expires_at, :repository_id], name: "index_exemption_requests_resource_identifier_and_repo"


    end
  end
end
