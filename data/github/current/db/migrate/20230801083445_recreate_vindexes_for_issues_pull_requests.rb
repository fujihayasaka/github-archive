# typed: true
class RecreateVindexesForIssuesPullRequests < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    # archived_assignments_id_ks_idx
    remove_vindex("archived_assignments", "archived_assignments_id_ks_idx", "id")

    drop_vindex("archived_assignments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_assignments_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_assignments" })
    create_vindex("archived_assignments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_assignments_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_assignments", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_assignments", "archived_assignments_id_ks_idx", "id")

    # archived_commit_comments_id_ks_idx
    remove_vindex("archived_commit_comments", "archived_commit_comments_id_ks_idx", "id")

    drop_vindex("archived_commit_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_commit_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_commit_comments" })
    create_vindex("archived_commit_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_commit_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_commit_comments", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_commit_comments", "archived_commit_comments_id_ks_idx", "id")

    # archived_deployment_statuses_id_ks_idx
    remove_vindex("archived_deployment_statuses", "archived_deployment_statuses_id_ks_idx", "id")

    drop_vindex("archived_deployment_statuses_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_deployment_statuses_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_deployment_statuses" })
    create_vindex("archived_deployment_statuses_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_deployment_statuses_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_deployment_statuses", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_deployment_statuses", "archived_deployment_statuses_id_ks_idx", "id")

    # archived_deployments_id_ks_idx
    remove_vindex("archived_deployments", "archived_deployments_id_ks_idx", "id")

    drop_vindex("archived_deployments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_deployments_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_deployments" })
    create_vindex("archived_deployments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_deployments_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_deployments", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_deployments", "archived_deployments_id_ks_idx", "id")

    # archived_issue_comments_id_ks_idx
    remove_vindex("archived_issue_comments", "archived_issue_comments_id_ks_idx", "id")

    drop_vindex("archived_issue_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_issue_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_issue_comments" })
    create_vindex("archived_issue_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_issue_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_issue_comments", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_issue_comments", "archived_issue_comments_id_ks_idx", "id")

    # archived_issue_event_details_id_ks_idx
    remove_vindex("archived_issue_event_details", "archived_issue_event_details_id_ks_idx", "id")

    drop_vindex("archived_issue_event_details_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_issue_event_details_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_issue_event_details" })
    create_vindex("archived_issue_event_details_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_issue_event_details_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_issue_event_details", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_issue_event_details", "archived_issue_event_details_id_ks_idx", "id")

    # archived_issue_events_id_ks_idx
    remove_vindex("archived_issue_events", "archived_issue_events_id_ks_idx", "id")

    drop_vindex("archived_issue_events_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_issue_events_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_issue_events" })
    create_vindex("archived_issue_events_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_issue_events_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_issue_events", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_issue_events", "archived_issue_events_id_ks_idx", "id")

    # archived_issues_id_ks_idx
    remove_vindex("archived_issues", "archived_issues_id_ks_idx", "id")

    drop_vindex("archived_issues_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_issues_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_issues" })
    create_vindex("archived_issues_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_issues_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_issues", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_issues", "archived_issues_id_ks_idx", "id")

    # archived_labels_id_ks_idx
    remove_vindex("archived_labels", "archived_labels_id_ks_idx", "id")

    drop_vindex("archived_labels_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_labels_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_labels" })
    create_vindex("archived_labels_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_labels_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_labels", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_labels", "archived_labels_id_ks_idx", "id")

    # archived_milestones_id_ks_idx
    remove_vindex("archived_milestones", "archived_milestones_id_ks_idx", "id")

    drop_vindex("archived_milestones_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_milestones_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_milestones" })
    create_vindex("archived_milestones_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_milestones_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_milestones", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_milestones", "archived_milestones_id_ks_idx", "id")

    # archived_pull_request_review_comments_id_ks_idx
    remove_vindex("archived_pull_request_review_comments", "archived_pull_request_review_comments_id_ks_idx", "id")

    drop_vindex("archived_pull_request_review_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_request_review_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_request_review_comments" })
    create_vindex("archived_pull_request_review_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_request_review_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_request_review_comments", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_pull_request_review_comments", "archived_pull_request_review_comments_id_ks_idx", "id")

    # archived_pull_request_review_points_id_ks_idx
    remove_vindex("archived_pull_request_review_points", "archived_pull_request_review_points_id_ks_idx", "id")

    drop_vindex("archived_pull_request_review_points_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_request_review_points_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_request_review_points" })
    create_vindex("archived_pull_request_review_points_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_request_review_points_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_request_review_points", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_pull_request_review_points", "archived_pull_request_review_points_id_ks_idx", "id")

    # archived_pull_request_review_threads_id_ks_idx
    remove_vindex("archived_pull_request_review_threads", "archived_pull_request_review_threads_id_ks_idx", "id")

    drop_vindex("archived_pull_request_review_threads_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_request_review_threads_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_request_review_threads" })
    create_vindex("archived_pull_request_review_threads_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_request_review_threads_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_request_review_threads", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_pull_request_review_threads", "archived_pull_request_review_threads_id_ks_idx", "id")

    # archived_pull_request_reviews_id_ks_idx
    remove_vindex("archived_pull_request_reviews", "archived_pull_request_reviews_id_ks_idx", "id")

    drop_vindex("archived_pull_request_reviews_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_request_reviews_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_request_reviews" })
    create_vindex("archived_pull_request_reviews_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_request_reviews_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_request_reviews", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_pull_request_reviews", "archived_pull_request_reviews_id_ks_idx", "id")

    # archived_pull_request_reviews_review_requests_id_ks_idx
    remove_vindex("archived_pull_request_reviews_review_requests", "archived_pull_request_reviews_review_requests_id_ks_idx", "id")

    drop_vindex("archived_pull_request_reviews_review_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_request_reviews_review_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_request_reviews_review_requests" })
    create_vindex("archived_pull_request_reviews_review_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_request_reviews_review_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_request_reviews_review_requests", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_pull_request_reviews_review_requests", "archived_pull_request_reviews_review_requests_id_ks_idx", "id")

    # archived_pull_request_updates_id_ks_idx
    remove_vindex("archived_pull_request_updates", "archived_pull_request_updates_id_ks_idx", "id")

    drop_vindex("archived_pull_request_updates_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_request_updates_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_request_updates" })
    create_vindex("archived_pull_request_updates_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_request_updates_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_request_updates", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_pull_request_updates", "archived_pull_request_updates_id_ks_idx", "id")

    # archived_pull_requests_id_ks_idx
    remove_vindex("archived_pull_requests", "archived_pull_requests_id_ks_idx", "id")

    drop_vindex("archived_pull_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_requests" })
    create_vindex("archived_pull_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_pull_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_pull_requests", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_pull_requests", "archived_pull_requests_id_ks_idx", "id")

    # archived_review_request_reasons_id_ks_idx
    remove_vindex("archived_review_request_reasons", "archived_review_request_reasons_id_ks_idx", "id")

    drop_vindex("archived_review_request_reasons_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_review_request_reasons_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_review_request_reasons" })
    create_vindex("archived_review_request_reasons_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_review_request_reasons_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_review_request_reasons", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_review_request_reasons", "archived_review_request_reasons_id_ks_idx", "id")

    # archived_review_requests_id_ks_idx
    remove_vindex("archived_review_requests", "archived_review_requests_id_ks_idx", "id")

    drop_vindex("archived_review_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_review_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_review_requests" })
    create_vindex("archived_review_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "archived_review_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "archived_review_requests", "autocommit" => true, "read_lock" => "none" })

    add_vindex("archived_review_requests", "archived_review_requests_id_ks_idx", "id")

    # assignments_id_ks_idx
    remove_vindex("assignments", "assignments_id_ks_idx", "id")

    drop_vindex("assignments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "assignments_id_ks_idx", "to" => "keyspace_id", "owner" => "assignments" })
    create_vindex("assignments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "assignments_id_ks_idx", "to" => "keyspace_id", "owner" => "assignments", "autocommit" => true, "read_lock" => "none" })

    add_vindex("assignments", "assignments_id_ks_idx", "id")

    # auto_merge_requests_id_ks_idx
    remove_vindex("auto_merge_requests", "auto_merge_requests_id_ks_idx", "id")

    drop_vindex("auto_merge_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "auto_merge_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "auto_merge_requests" })
    create_vindex("auto_merge_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "auto_merge_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "auto_merge_requests", "autocommit" => true, "read_lock" => "none" })

    add_vindex("auto_merge_requests", "auto_merge_requests_id_ks_idx", "id")

    # code_scanning_review_comments_id_ks_idx
    remove_vindex("code_scanning_review_comments", "code_scanning_review_comments_id_ks_idx", "id")

    drop_vindex("code_scanning_review_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "code_scanning_review_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "code_scanning_review_comments" })
    create_vindex("code_scanning_review_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "code_scanning_review_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "code_scanning_review_comments", "autocommit" => true, "read_lock" => "none" })

    add_vindex("code_scanning_review_comments", "code_scanning_review_comments_id_ks_idx", "id")

    # commit_comment_edits_id_ks_idx
    remove_vindex("commit_comment_edits", "commit_comment_edits_id_ks_idx", "id")

    drop_vindex("commit_comment_edits_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "commit_comment_edits_id_ks_idx", "to" => "keyspace_id", "owner" => "commit_comment_edits" })
    create_vindex("commit_comment_edits_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "commit_comment_edits_id_ks_idx", "to" => "keyspace_id", "owner" => "commit_comment_edits", "autocommit" => true, "read_lock" => "none" })

    add_vindex("commit_comment_edits", "commit_comment_edits_id_ks_idx", "id")

    # commit_comment_reactions_id_ks_idx
    remove_vindex("commit_comment_reactions", "commit_comment_reactions_id_ks_idx", "id")

    drop_vindex("commit_comment_reactions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "commit_comment_reactions_id_ks_idx", "to" => "keyspace_id", "owner" => "commit_comment_reactions" })
    create_vindex("commit_comment_reactions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "commit_comment_reactions_id_ks_idx", "to" => "keyspace_id", "owner" => "commit_comment_reactions", "autocommit" => true, "read_lock" => "none" })

    add_vindex("commit_comment_reactions", "commit_comment_reactions_id_ks_idx", "id")

    # commit_comments_id_ks_idx
    remove_vindex("commit_comment_edits", "commit_comments_id_ks_idx", "commit_comment_id")
    remove_vindex("commit_comment_reactions", "commit_comments_id_ks_idx", "commit_comment_id")
    remove_vindex("commit_comments", "commit_comments_id_ks_idx", "id")

    drop_vindex("commit_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "commit_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "commit_comments" })
    create_vindex("commit_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "commit_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "commit_comments", "autocommit" => true, "read_lock" => "none" })

    add_vindex("commit_comment_edits", "commit_comments_id_ks_idx", "commit_comment_id")
    add_vindex("commit_comment_reactions", "commit_comments_id_ks_idx", "commit_comment_id")
    add_vindex("commit_comments", "commit_comments_id_ks_idx", "id")

    # commit_comment_edits_on_user_content_edit_id_ks_idx
    remove_vindex("commit_comment_edits", "commit_comment_edits_on_user_content_edit_id_ks_idx", "user_content_edit_id")

    drop_vindex("commit_comment_edits_on_user_content_edit_id_ks_idx", "lookup_unique", { "from" => "user_content_edit_id", "ignore_nulls" => "true", "table" => "commit_comment_edits_on_user_content_edit_id_ks_idx", "to" => "keyspace_id", "owner" => "commit_comment_edits" })
    create_vindex("commit_comment_edits_on_user_content_edit_id_ks_idx", "lookup_unique", { "from" => "user_content_edit_id", "ignore_nulls" => "true", "table" => "commit_comment_edits_on_user_content_edit_id_ks_idx", "to" => "keyspace_id", "owner" => "commit_comment_edits", "autocommit" => true, "read_lock" => "none" })

    add_vindex("commit_comment_edits", "commit_comment_edits_on_user_content_edit_id_ks_idx", "user_content_edit_id")

    # commit_mentions_id_ks_idx
    remove_vindex("commit_mentions", "commit_mentions_id_ks_idx", "id")

    drop_vindex("commit_mentions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "commit_mentions_id_ks_idx", "to" => "keyspace_id", "owner" => "commit_mentions" })
    create_vindex("commit_mentions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "commit_mentions_id_ks_idx", "to" => "keyspace_id", "owner" => "commit_mentions", "autocommit" => true, "read_lock" => "none" })

    add_vindex("commit_mentions", "commit_mentions_id_ks_idx", "id")

    # cross_references_id_ks_idx
    remove_vindex("cross_references", "cross_references_id_ks_idx", "id")

    drop_vindex("cross_references_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "cross_references_id_ks_idx", "to" => "keyspace_id", "owner" => "cross_references" })
    create_vindex("cross_references_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "cross_references_id_ks_idx", "to" => "keyspace_id", "owner" => "cross_references", "autocommit" => true, "read_lock" => "none" })

    add_vindex("cross_references", "cross_references_id_ks_idx", "id")

    # deployment_statuses_id_ks_idx
    remove_vindex("deployment_statuses", "deployment_statuses_id_ks_idx", "id")
    remove_vindex("deployments", "deployment_statuses_id_ks_idx", "latest_deployment_status_id")

    drop_vindex("deployment_statuses_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "deployment_statuses_id_ks_idx", "to" => "keyspace_id", "owner" => "deployment_statuses" })
    create_vindex("deployment_statuses_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "deployment_statuses_id_ks_idx", "to" => "keyspace_id", "owner" => "deployment_statuses", "autocommit" => true, "read_lock" => "none" })

    add_vindex("deployment_statuses", "deployment_statuses_id_ks_idx", "id")
    add_vindex("deployments", "deployment_statuses_id_ks_idx", "latest_deployment_status_id")

    # deployments_id_ks_idx
    remove_vindex("deployment_statuses", "deployments_id_ks_idx", "deployment_id")
    remove_vindex("deployments", "deployments_id_ks_idx", "id")

    drop_vindex("deployments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "deployments_id_ks_idx", "to" => "keyspace_id", "owner" => "deployments" })
    create_vindex("deployments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "deployments_id_ks_idx", "to" => "keyspace_id", "owner" => "deployments", "autocommit" => true, "read_lock" => "none" })

    add_vindex("deployment_statuses", "deployments_id_ks_idx", "deployment_id")
    add_vindex("deployments", "deployments_id_ks_idx", "id")

    # duplicate_issues_id_ks_idx
    remove_vindex("duplicate_issues", "duplicate_issues_id_ks_idx", "id")

    drop_vindex("duplicate_issues_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "duplicate_issues_id_ks_idx", "to" => "keyspace_id", "owner" => "duplicate_issues" })
    create_vindex("duplicate_issues_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "duplicate_issues_id_ks_idx", "to" => "keyspace_id", "owner" => "duplicate_issues", "autocommit" => true, "read_lock" => "none" })

    add_vindex("duplicate_issues", "duplicate_issues_id_ks_idx", "id")

    # issue_alert_links_id_ks_idx
    remove_vindex("issue_alert_links", "issue_alert_links_id_ks_idx", "id")

    drop_vindex("issue_alert_links_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_alert_links_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_alert_links" })
    create_vindex("issue_alert_links_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_alert_links_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_alert_links", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_alert_links", "issue_alert_links_id_ks_idx", "id")

    # issue_blob_references_id_ks_idx
    remove_vindex("issue_blob_references", "issue_blob_references_id_ks_idx", "id")

    drop_vindex("issue_blob_references_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_blob_references_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_blob_references" })
    create_vindex("issue_blob_references_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_blob_references_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_blob_references", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_blob_references", "issue_blob_references_id_ks_idx", "id")

    # issue_comment_edits_id_ks_idx
    remove_vindex("issue_comment_edits", "issue_comment_edits_id_ks_idx", "id")

    drop_vindex("issue_comment_edits_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_comment_edits_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_comment_edits" })
    create_vindex("issue_comment_edits_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_comment_edits_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_comment_edits", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_comment_edits", "issue_comment_edits_id_ks_idx", "id")

    # issue_comment_meta_data_blobs_id_ks_idx
    remove_vindex("issue_comment_meta_data_blobs", "issue_comment_meta_data_blobs_id_ks_idx", "id")

    drop_vindex("issue_comment_meta_data_blobs_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_comment_meta_data_blobs_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_comment_meta_data_blobs" })
    create_vindex("issue_comment_meta_data_blobs_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_comment_meta_data_blobs_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_comment_meta_data_blobs", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_comment_meta_data_blobs", "issue_comment_meta_data_blobs_id_ks_idx", "id")

    # issue_comment_reactions_id_ks_idx
    remove_vindex("issue_comment_reactions", "issue_comment_reactions_id_ks_idx", "id")

    drop_vindex("issue_comment_reactions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_comment_reactions_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_comment_reactions" })
    create_vindex("issue_comment_reactions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_comment_reactions_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_comment_reactions", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_comment_reactions", "issue_comment_reactions_id_ks_idx", "id")

    # issue_comments_id_ks_idx
    remove_vindex("issue_comment_edits", "issue_comments_id_ks_idx", "issue_comment_id")
    remove_vindex("issue_comment_meta_data_blobs", "issue_comments_id_ks_idx", "issue_comment_id")
    remove_vindex("issue_comment_reactions", "issue_comments_id_ks_idx", "issue_comment_id")
    remove_vindex("issue_comments", "issue_comments_id_ks_idx", "id")

    drop_vindex("issue_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_comments" })
    create_vindex("issue_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_comments", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_comment_edits", "issue_comments_id_ks_idx", "issue_comment_id")
    add_vindex("issue_comment_meta_data_blobs", "issue_comments_id_ks_idx", "issue_comment_id")
    add_vindex("issue_comment_reactions", "issue_comments_id_ks_idx", "issue_comment_id")
    add_vindex("issue_comments", "issue_comments_id_ks_idx", "id")

    # issue_comment_edits_on_user_content_edit_id_ks_idx
    remove_vindex("issue_comment_edits", "issue_comment_edits_on_user_content_edit_id_ks_idx", "user_content_edit_id")

    drop_vindex("issue_comment_edits_on_user_content_edit_id_ks_idx", "lookup_unique", { "from" => "user_content_edit_id", "ignore_nulls" => "true", "table" => "issue_comment_edits_on_user_content_edit_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_comment_edits" })
    create_vindex("issue_comment_edits_on_user_content_edit_id_ks_idx", "lookup_unique", { "from" => "user_content_edit_id", "ignore_nulls" => "true", "table" => "issue_comment_edits_on_user_content_edit_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_comment_edits", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_comment_edits", "issue_comment_edits_on_user_content_edit_id_ks_idx", "user_content_edit_id")

    # issue_edits_id_ks_idx
    remove_vindex("issue_edits", "issue_edits_id_ks_idx", "id")

    drop_vindex("issue_edits_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_edits_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_edits" })
    create_vindex("issue_edits_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_edits_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_edits", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_edits", "issue_edits_id_ks_idx", "id")

    # issue_event_details_id_ks_idx
    remove_vindex("issue_event_details", "issue_event_details_id_ks_idx", "id")

    drop_vindex("issue_event_details_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_event_details_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_event_details" })
    create_vindex("issue_event_details_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_event_details_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_event_details", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_event_details", "issue_event_details_id_ks_idx", "id")

    # issue_events_id_ks_idx
    remove_vindex("issue_event_details", "issue_events_id_ks_idx", "issue_event_id")
    remove_vindex("issue_events", "issue_events_id_ks_idx", "id")

    drop_vindex("issue_events_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_events_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_events" })
    create_vindex("issue_events_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_events_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_events", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_event_details", "issue_events_id_ks_idx", "issue_event_id")
    add_vindex("issue_events", "issue_events_id_ks_idx", "id")

    # issue_links_id_ks_idx
    remove_vindex("issue_links", "issue_links_id_ks_idx", "id")

    drop_vindex("issue_links_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_links_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_links" })
    create_vindex("issue_links_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_links_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_links", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_links", "issue_links_id_ks_idx", "id")

    # issue_priorities_id_ks_idx
    remove_vindex("issue_priorities", "issue_priorities_id_ks_idx", "id")

    drop_vindex("issue_priorities_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_priorities_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_priorities" })
    create_vindex("issue_priorities_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_priorities_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_priorities", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_priorities", "issue_priorities_id_ks_idx", "id")

    # issue_reactions_id_ks_idx
    remove_vindex("issue_reactions", "issue_reactions_id_ks_idx", "id")

    drop_vindex("issue_reactions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_reactions_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_reactions" })
    create_vindex("issue_reactions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_reactions_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_reactions", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_reactions", "issue_reactions_id_ks_idx", "id")

    # issues_id_ks_idx
    remove_vindex("assignments", "issues_id_ks_idx", "issue_id")
    remove_vindex("duplicate_issues", "issues_id_ks_idx", "issue_id")
    remove_vindex("issue_blob_references", "issues_id_ks_idx", "issue_id")
    remove_vindex("issue_comments", "issues_id_ks_idx", "issue_id")
    remove_vindex("issue_edits", "issues_id_ks_idx", "issue_id")
    remove_vindex("issue_events", "issues_id_ks_idx", "issue_id")
    remove_vindex("issue_links", "issues_id_ks_idx", "source_issue_id")
    remove_vindex("issue_orchestrations", "issues_id_ks_idx", "issue_id")
    remove_vindex("issue_priorities", "issues_id_ks_idx", "issue_id")
    remove_vindex("issue_reactions", "issues_id_ks_idx", "issue_id")
    remove_vindex("issues", "issues_id_ks_idx", "id")
    remove_vindex("issues_labels", "issues_id_ks_idx", "issue_id")

    drop_vindex("issues_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issues_id_ks_idx", "to" => "keyspace_id", "owner" => "issues" })
    create_vindex("issues_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issues_id_ks_idx", "to" => "keyspace_id", "owner" => "issues", "autocommit" => true, "read_lock" => "none" })

    add_vindex("assignments", "issues_id_ks_idx", "issue_id")
    add_vindex("duplicate_issues", "issues_id_ks_idx", "issue_id")
    add_vindex("issue_blob_references", "issues_id_ks_idx", "issue_id")
    add_vindex("issue_comments", "issues_id_ks_idx", "issue_id")
    add_vindex("issue_edits", "issues_id_ks_idx", "issue_id")
    add_vindex("issue_events", "issues_id_ks_idx", "issue_id")
    add_vindex("issue_links", "issues_id_ks_idx", "source_issue_id")
    add_vindex("issue_orchestrations", "issues_id_ks_idx", "issue_id")
    add_vindex("issue_priorities", "issues_id_ks_idx", "issue_id")
    add_vindex("issue_reactions", "issues_id_ks_idx", "issue_id")
    add_vindex("issues", "issues_id_ks_idx", "id")
    add_vindex("issues_labels", "issues_id_ks_idx", "issue_id")

    # issue_edits_on_user_content_edit_id_ks_idx
    remove_vindex("issue_edits", "issue_edits_on_user_content_edit_id_ks_idx", "user_content_edit_id")

    drop_vindex("issue_edits_on_user_content_edit_id_ks_idx", "lookup_unique", { "from" => "user_content_edit_id", "ignore_nulls" => "true", "table" => "issue_edits_on_user_content_edit_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_edits" })
    create_vindex("issue_edits_on_user_content_edit_id_ks_idx", "lookup_unique", { "from" => "user_content_edit_id", "ignore_nulls" => "true", "table" => "issue_edits_on_user_content_edit_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_edits", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_edits", "issue_edits_on_user_content_edit_id_ks_idx", "user_content_edit_id")

    # issue_imports_id_ks_idx
    remove_vindex("issue_imports", "issue_imports_id_ks_idx", "id")

    drop_vindex("issue_imports_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_imports_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_imports" })
    create_vindex("issue_imports_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_imports_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_imports", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_imports", "issue_imports_id_ks_idx", "id")

    # issue_orchestrations_id_ks_idx
    remove_vindex("issue_orchestrations", "issue_orchestrations_id_ks_idx", "id")

    drop_vindex("issue_orchestrations_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_orchestrations_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_orchestrations" })
    create_vindex("issue_orchestrations_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issue_orchestrations_id_ks_idx", "to" => "keyspace_id", "owner" => "issue_orchestrations", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_orchestrations", "issue_orchestrations_id_ks_idx", "id")

    # issues_labels_id_ks_idx
    remove_vindex("issues_labels", "issues_labels_id_ks_idx", "id")

    drop_vindex("issues_labels_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issues_labels_id_ks_idx", "to" => "keyspace_id", "owner" => "issues_labels" })
    create_vindex("issues_labels_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "issues_labels_id_ks_idx", "to" => "keyspace_id", "owner" => "issues_labels", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issues_labels", "issues_labels_id_ks_idx", "id")

    # labels_id_ks_idx
    remove_vindex("issues_labels", "labels_id_ks_idx", "label_id")
    remove_vindex("labels", "labels_id_ks_idx", "id")

    drop_vindex("labels_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "labels_id_ks_idx", "to" => "keyspace_id", "owner" => "labels" })
    create_vindex("labels_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "labels_id_ks_idx", "to" => "keyspace_id", "owner" => "labels", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issues_labels", "labels_id_ks_idx", "label_id")
    add_vindex("labels", "labels_id_ks_idx", "id")

    # last_seen_pull_request_revisions_id_ks_idx
    remove_vindex("last_seen_pull_request_revisions", "last_seen_pull_request_revisions_id_ks_idx", "id")

    drop_vindex("last_seen_pull_request_revisions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "last_seen_pull_request_revisions_id_ks_idx", "to" => "keyspace_id", "owner" => "last_seen_pull_request_revisions" })
    create_vindex("last_seen_pull_request_revisions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "last_seen_pull_request_revisions_id_ks_idx", "to" => "keyspace_id", "owner" => "last_seen_pull_request_revisions", "autocommit" => true, "read_lock" => "none" })

    add_vindex("last_seen_pull_request_revisions", "last_seen_pull_request_revisions_id_ks_idx", "id")

    # milestones_id_ks_idx
    remove_vindex("issue_priorities", "milestones_id_ks_idx", "milestone_id")
    remove_vindex("issues", "milestones_id_ks_idx", "milestone_id")
    remove_vindex("milestones", "milestones_id_ks_idx", "id")

    drop_vindex("milestones_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "milestones_id_ks_idx", "to" => "keyspace_id", "owner" => "milestones" })
    create_vindex("milestones_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "milestones_id_ks_idx", "to" => "keyspace_id", "owner" => "milestones", "autocommit" => true, "read_lock" => "none" })

    add_vindex("issue_priorities", "milestones_id_ks_idx", "milestone_id")
    add_vindex("issues", "milestones_id_ks_idx", "milestone_id")
    add_vindex("milestones", "milestones_id_ks_idx", "id")

    # pull_request_conflicts_id_ks_idx
    remove_vindex("pull_request_conflicts", "pull_request_conflicts_id_ks_idx", "id")

    drop_vindex("pull_request_conflicts_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_conflicts_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_conflicts" })
    create_vindex("pull_request_conflicts_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_conflicts_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_conflicts", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_conflicts", "pull_request_conflicts_id_ks_idx", "id")

    # pull_request_review_comments_id_ks_idx
    remove_vindex("code_scanning_review_comments", "pull_request_review_comments_id_ks_idx", "pull_request_review_comment_id")
    remove_vindex("pull_request_review_comment_edits", "pull_request_review_comments_id_ks_idx", "pull_request_review_comment_id")
    remove_vindex("pull_request_review_comment_orchestrations", "pull_request_review_comments_id_ks_idx", "pull_request_review_comment_id")
    remove_vindex("pull_request_review_comment_reactions", "pull_request_review_comments_id_ks_idx", "pull_request_review_comment_id")
    remove_vindex("pull_request_review_comments", "pull_request_review_comments_id_ks_idx", "id")

    drop_vindex("pull_request_review_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_comments" })
    create_vindex("pull_request_review_comments_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_comments_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_comments", "autocommit" => true, "read_lock" => "none" })

    add_vindex("code_scanning_review_comments", "pull_request_review_comments_id_ks_idx", "pull_request_review_comment_id")
    add_vindex("pull_request_review_comment_edits", "pull_request_review_comments_id_ks_idx", "pull_request_review_comment_id")
    add_vindex("pull_request_review_comment_orchestrations", "pull_request_review_comments_id_ks_idx", "pull_request_review_comment_id")
    add_vindex("pull_request_review_comment_reactions", "pull_request_review_comments_id_ks_idx", "pull_request_review_comment_id")
    add_vindex("pull_request_review_comments", "pull_request_review_comments_id_ks_idx", "id")

    # pull_request_review_threads_id_ks_idx
    remove_vindex("pull_request_review_comments", "pull_request_review_threads_id_ks_idx", "pull_request_review_thread_id")
    remove_vindex("pull_request_review_threads", "pull_request_review_threads_id_ks_idx", "id")

    drop_vindex("pull_request_review_threads_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_threads_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_threads" })
    create_vindex("pull_request_review_threads_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_threads_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_threads", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_review_comments", "pull_request_review_threads_id_ks_idx", "pull_request_review_thread_id")
    add_vindex("pull_request_review_threads", "pull_request_review_threads_id_ks_idx", "id")

    # pull_request_review_points_id_ks_idx
    remove_vindex("pull_request_review_points", "pull_request_review_points_id_ks_idx", "id")

    drop_vindex("pull_request_review_points_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_points_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_points" })
    create_vindex("pull_request_review_points_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_points_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_points", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_review_points", "pull_request_review_points_id_ks_idx", "id")

    # pull_request_updates_id_ks_idx
    remove_vindex("pull_request_review_points", "pull_request_updates_id_ks_idx", "pull_request_update_id")
    remove_vindex("pull_request_updates", "pull_request_updates_id_ks_idx", "id")

    drop_vindex("pull_request_updates_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_updates_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_updates" })
    create_vindex("pull_request_updates_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_updates_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_updates", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_review_points", "pull_request_updates_id_ks_idx", "pull_request_update_id")
    add_vindex("pull_request_updates", "pull_request_updates_id_ks_idx", "id")

    # pull_requests_id_ks_idx
    remove_vindex("auto_merge_requests", "pull_requests_id_ks_idx", "pull_request_id")
    remove_vindex("issues", "pull_requests_id_ks_idx", "pull_request_id")
    remove_vindex("last_seen_pull_request_revisions", "pull_requests_id_ks_idx", "pull_request_id")
    remove_vindex("pull_request_conflicts", "pull_requests_id_ks_idx", "pull_request_id")
    remove_vindex("pull_request_orchestrations", "pull_requests_id_ks_idx", "pull_request_id")
    remove_vindex("pull_request_review_comment_orchestrations", "pull_requests_id_ks_idx", "pull_request_id")
    remove_vindex("pull_request_review_comments", "pull_requests_id_ks_idx", "pull_request_id")
    remove_vindex("pull_request_review_points", "pull_requests_id_ks_idx", "pull_request_id")
    remove_vindex("pull_request_review_threads", "pull_requests_id_ks_idx", "pull_request_id")
    remove_vindex("pull_request_reviews", "pull_requests_id_ks_idx", "pull_request_id")
    remove_vindex("pull_request_sources", "pull_requests_id_ks_idx", "pull_request_id")
    remove_vindex("pull_request_updates", "pull_requests_id_ks_idx", "pull_request_id")
    remove_vindex("pull_requests", "pull_requests_id_ks_idx", "id")
    remove_vindex("review_requests", "pull_requests_id_ks_idx", "pull_request_id")

    drop_vindex("pull_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_requests" })
    create_vindex("pull_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_requests", "autocommit" => true, "read_lock" => "none" })

    add_vindex("auto_merge_requests", "pull_requests_id_ks_idx", "pull_request_id")
    add_vindex("issues", "pull_requests_id_ks_idx", "pull_request_id")
    add_vindex("last_seen_pull_request_revisions", "pull_requests_id_ks_idx", "pull_request_id")
    add_vindex("pull_request_conflicts", "pull_requests_id_ks_idx", "pull_request_id")
    add_vindex("pull_request_orchestrations", "pull_requests_id_ks_idx", "pull_request_id")
    add_vindex("pull_request_review_comment_orchestrations", "pull_requests_id_ks_idx", "pull_request_id")
    add_vindex("pull_request_review_comments", "pull_requests_id_ks_idx", "pull_request_id")
    add_vindex("pull_request_review_points", "pull_requests_id_ks_idx", "pull_request_id")
    add_vindex("pull_request_review_threads", "pull_requests_id_ks_idx", "pull_request_id")
    add_vindex("pull_request_reviews", "pull_requests_id_ks_idx", "pull_request_id")
    add_vindex("pull_request_sources", "pull_requests_id_ks_idx", "pull_request_id")
    add_vindex("pull_request_updates", "pull_requests_id_ks_idx", "pull_request_id")
    add_vindex("pull_requests", "pull_requests_id_ks_idx", "id")
    add_vindex("review_requests", "pull_requests_id_ks_idx", "pull_request_id")

    # pull_request_orchestrations_id_ks_idx
    remove_vindex("pull_request_orchestrations", "pull_request_orchestrations_id_ks_idx", "id")

    drop_vindex("pull_request_orchestrations_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_orchestrations_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_orchestrations" })
    create_vindex("pull_request_orchestrations_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_orchestrations_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_orchestrations", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_orchestrations", "pull_request_orchestrations_id_ks_idx", "id")

    # pull_request_review_comment_edits_id_ks_idx
    remove_vindex("pull_request_review_comment_edits", "pull_request_review_comment_edits_id_ks_idx", "id")

    drop_vindex("pull_request_review_comment_edits_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_comment_edits_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_comment_edits" })
    create_vindex("pull_request_review_comment_edits_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_comment_edits_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_comment_edits", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_review_comment_edits", "pull_request_review_comment_edits_id_ks_idx", "id")

    # pull_request_review_comment_reactions_id_ks_idx
    remove_vindex("pull_request_review_comment_reactions", "pull_request_review_comment_reactions_id_ks_idx", "id")

    drop_vindex("pull_request_review_comment_reactions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_comment_reactions_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_comment_reactions" })
    create_vindex("pull_request_review_comment_reactions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_comment_reactions_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_comment_reactions", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_review_comment_reactions", "pull_request_review_comment_reactions_id_ks_idx", "id")

    # pull_request_review_comment_edits_on_user_content_edit_id_ks_idx
    remove_vindex("pull_request_review_comment_edits", "pull_request_review_comment_edits_on_user_content_edit_id_ks_idx", "user_content_edit_id")

    drop_vindex("pull_request_review_comment_edits_on_user_content_edit_id_ks_idx", "lookup_unique", { "from" => "user_content_edit_id", "ignore_nulls" => "true", "table" => "pull_request_review_comment_edits_on_user_content_edit_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_comment_edits" })
    create_vindex("pull_request_review_comment_edits_on_user_content_edit_id_ks_idx", "lookup_unique", { "from" => "user_content_edit_id", "ignore_nulls" => "true", "table" => "pull_request_review_comment_edits_on_user_content_edit_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_comment_edits", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_review_comment_edits", "pull_request_review_comment_edits_on_user_content_edit_id_ks_idx", "user_content_edit_id")

    # pull_request_review_comment_orchestrations_id_ks_idx
    remove_vindex("pull_request_review_comment_orchestrations", "pull_request_review_comment_orchestrations_id_ks_idx", "id")

    drop_vindex("pull_request_review_comment_orchestrations_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_comment_orchestrations_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_comment_orchestrations" })
    create_vindex("pull_request_review_comment_orchestrations_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_comment_orchestrations_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_comment_orchestrations", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_review_comment_orchestrations", "pull_request_review_comment_orchestrations_id_ks_idx", "id")

    # pull_request_review_edits_id_ks_idx
    remove_vindex("pull_request_review_edits", "pull_request_review_edits_id_ks_idx", "id")

    drop_vindex("pull_request_review_edits_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_edits_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_edits" })
    create_vindex("pull_request_review_edits_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_edits_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_edits", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_review_edits", "pull_request_review_edits_id_ks_idx", "id")

    # pull_request_review_reactions_id_ks_idx
    remove_vindex("pull_request_review_reactions", "pull_request_review_reactions_id_ks_idx", "id")

    drop_vindex("pull_request_review_reactions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_reactions_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_reactions" })
    create_vindex("pull_request_review_reactions_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_review_reactions_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_reactions", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_review_reactions", "pull_request_review_reactions_id_ks_idx", "id")

    # pull_request_reviews_id_ks_idx
    remove_vindex("pull_request_review_comments", "pull_request_reviews_id_ks_idx", "pull_request_review_id")
    remove_vindex("pull_request_review_edits", "pull_request_reviews_id_ks_idx", "pull_request_review_id")
    remove_vindex("pull_request_review_reactions", "pull_request_reviews_id_ks_idx", "pull_request_review_id")
    remove_vindex("pull_request_review_threads", "pull_request_reviews_id_ks_idx", "pull_request_review_id")
    remove_vindex("pull_request_reviews", "pull_request_reviews_id_ks_idx", "id")
    remove_vindex("pull_request_reviews_review_requests", "pull_request_reviews_id_ks_idx", "pull_request_review_id")

    drop_vindex("pull_request_reviews_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_reviews_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_reviews" })
    create_vindex("pull_request_reviews_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_reviews_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_reviews", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_review_comments", "pull_request_reviews_id_ks_idx", "pull_request_review_id")
    add_vindex("pull_request_review_edits", "pull_request_reviews_id_ks_idx", "pull_request_review_id")
    add_vindex("pull_request_review_reactions", "pull_request_reviews_id_ks_idx", "pull_request_review_id")
    add_vindex("pull_request_review_threads", "pull_request_reviews_id_ks_idx", "pull_request_review_id")
    add_vindex("pull_request_reviews", "pull_request_reviews_id_ks_idx", "id")
    add_vindex("pull_request_reviews_review_requests", "pull_request_reviews_id_ks_idx", "pull_request_review_id")

    # pull_request_review_edits_on_user_content_edit_id_ks_idx
    remove_vindex("pull_request_review_edits", "pull_request_review_edits_on_user_content_edit_id_ks_idx", "user_content_edit_id")

    drop_vindex("pull_request_review_edits_on_user_content_edit_id_ks_idx", "lookup_unique", { "from" => "user_content_edit_id", "ignore_nulls" => "true", "table" => "pull_request_review_edits_on_user_content_edit_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_edits" })
    create_vindex("pull_request_review_edits_on_user_content_edit_id_ks_idx", "lookup_unique", { "from" => "user_content_edit_id", "ignore_nulls" => "true", "table" => "pull_request_review_edits_on_user_content_edit_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_review_edits", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_review_edits", "pull_request_review_edits_on_user_content_edit_id_ks_idx", "user_content_edit_id")

    # pull_request_reviews_review_requests_id_ks_idx
    remove_vindex("pull_request_reviews_review_requests", "pull_request_reviews_review_requests_id_ks_idx", "id")

    drop_vindex("pull_request_reviews_review_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_reviews_review_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_reviews_review_requests" })
    create_vindex("pull_request_reviews_review_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_reviews_review_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_reviews_review_requests", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_reviews_review_requests", "pull_request_reviews_review_requests_id_ks_idx", "id")

    # pull_request_sources_id_ks_idx
    remove_vindex("pull_request_sources", "pull_request_sources_id_ks_idx", "id")

    drop_vindex("pull_request_sources_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_sources_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_sources" })
    create_vindex("pull_request_sources_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "pull_request_sources_id_ks_idx", "to" => "keyspace_id", "owner" => "pull_request_sources", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_sources", "pull_request_sources_id_ks_idx", "id")

    # repository_milestones_sequences_id_ks_idx
    remove_vindex("repository_milestones_sequences", "repository_milestones_sequences_id_ks_idx", "id")

    drop_vindex("repository_milestones_sequences_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "repository_milestones_sequences_id_ks_idx", "to" => "keyspace_id", "owner" => "repository_milestones_sequences" })
    create_vindex("repository_milestones_sequences_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "repository_milestones_sequences_id_ks_idx", "to" => "keyspace_id", "owner" => "repository_milestones_sequences", "autocommit" => true, "read_lock" => "none" })

    add_vindex("repository_milestones_sequences", "repository_milestones_sequences_id_ks_idx", "id")

    # repository_properties_id_ks_idx
    remove_vindex("repository_properties", "repository_properties_id_ks_idx", "id")

    drop_vindex("repository_properties_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "repository_properties_id_ks_idx", "to" => "keyspace_id", "owner" => "repository_properties" })
    create_vindex("repository_properties_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "repository_properties_id_ks_idx", "to" => "keyspace_id", "owner" => "repository_properties", "autocommit" => true, "read_lock" => "none" })

    add_vindex("repository_properties", "repository_properties_id_ks_idx", "id")

    # review_request_reasons_id_ks_idx
    remove_vindex("review_request_reasons", "review_request_reasons_id_ks_idx", "id")

    drop_vindex("review_request_reasons_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "review_request_reasons_id_ks_idx", "to" => "keyspace_id", "owner" => "review_request_reasons" })
    create_vindex("review_request_reasons_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "review_request_reasons_id_ks_idx", "to" => "keyspace_id", "owner" => "review_request_reasons", "autocommit" => true, "read_lock" => "none" })

    add_vindex("review_request_reasons", "review_request_reasons_id_ks_idx", "id")

    # review_requests_id_ks_idx
    remove_vindex("pull_request_reviews_review_requests", "review_requests_id_ks_idx", "review_request_id")
    remove_vindex("review_request_reasons", "review_requests_id_ks_idx", "review_request_id")
    remove_vindex("review_requests", "review_requests_id_ks_idx", "id")

    drop_vindex("review_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "review_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "review_requests" })
    create_vindex("review_requests_id_ks_idx", "lookup_unique", { "from" => "id", "table" => "review_requests_id_ks_idx", "to" => "keyspace_id", "owner" => "review_requests", "autocommit" => true, "read_lock" => "none" })

    add_vindex("pull_request_reviews_review_requests", "review_requests_id_ks_idx", "review_request_id")
    add_vindex("review_request_reasons", "review_requests_id_ks_idx", "review_request_id")
    add_vindex("review_requests", "review_requests_id_ks_idx", "id")
  end
end
