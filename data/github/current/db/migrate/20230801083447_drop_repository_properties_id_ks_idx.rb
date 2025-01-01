# typed: true

class DropRepositoryPropertiesIdKsIdx < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    remove_vindex("repository_properties", "repository_properties_id_ks_idx", "id")
    drop_vindex("repository_properties_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "repository_properties_id_ks_idx", "to" => "keyspace_id", "owner" => "repository_properties", "autocommit" => true, "read_lock" => "none" })

    drop_table :repository_properties_id_ks_idx
  end
end
