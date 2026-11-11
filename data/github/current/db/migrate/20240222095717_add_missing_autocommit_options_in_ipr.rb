class AddMissingAutocommitOptionsInIpr < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    # issue_comment_orchestrations_id_ks_idx on issue_comment_orchestrations
    remove_vindex("issue_comment_orchestrations", "issue_comment_orchestrations_id_ks_idx", "id")

    drop_vindex("issue_comment_orchestrations_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_comment_orchestrations_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_comment_orchestrations" })
    create_vindex("issue_comment_orchestrations_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_comment_orchestrations_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_comment_orchestrations", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_comment_orchestrations", "issue_comment_orchestrations_id_ks_idx", "id")

    # issue_types_id_ks_idx on issue_types
    remove_vindex("issue_types", "issue_types_id_ks_idx", "id")

    drop_vindex("issue_types_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_types_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_types" })
    create_vindex("issue_types_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_types_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_types", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_types", "issue_types_id_ks_idx", "id")

    # repository_issue_types_id_ks_idx on repository_issue_types
    remove_vindex("repository_issue_types", "repository_issue_types_id_ks_idx", "id")

    drop_vindex("repository_issue_types_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "repository_issue_types_id_ks_idx", "to" => "keyspace_id", "owner" => "repository_issue_types" })
    create_vindex("repository_issue_types_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "repository_issue_types_id_ks_idx", "to" => "keyspace_id", "owner" => "repository_issue_types", "autocommit" => true, "read_lock" => "none" })

    add_vindex("repository_issue_types", "repository_issue_types_id_ks_idx", "id")
  end
end
