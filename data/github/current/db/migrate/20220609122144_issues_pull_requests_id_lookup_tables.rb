# typed: true
# rubocop:disable GitHub/UseAppropriateDisplayWidth
# rubocop:disable GitHub/OneTablePerMigration
# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
# rubocop:disable GitHub/SpecifyDefaultCharsetAndCollation
class IssuesPullRequestsIdLookupTables < ActiveRecord::Migration[7.1]
  # See https://thehub.github.com/engineering/development-and-ops/dotcom/migrations-and-transitions/database-migrations-for-dotcom/ for tips
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    create_table :archived_assignments_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_assignments_id_ks_idx, :hash, :id

    create_vindex :archived_assignments_id_ks_idx, :lookup_unique, owner: "archived_assignments", from: "id", table: "archived_assignments_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_assignments, :archived_assignments_id_ks_idx, :id

    create_table :archived_commit_comments_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_commit_comments_id_ks_idx, :hash, :id

    create_vindex :archived_commit_comments_id_ks_idx, :lookup_unique, owner: "archived_commit_comments", from: "id", table: "archived_commit_comments_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_commit_comments, :archived_commit_comments_id_ks_idx, :id

    create_table :archived_deployment_statuses_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_deployment_statuses_id_ks_idx, :hash, :id

    create_vindex :archived_deployment_statuses_id_ks_idx, :lookup_unique, owner: "archived_deployment_statuses", from: "id", table: "archived_deployment_statuses_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_deployment_statuses, :archived_deployment_statuses_id_ks_idx, :id

    create_table :archived_deployments_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_deployments_id_ks_idx, :hash, :id

    create_vindex :archived_deployments_id_ks_idx, :lookup_unique, owner: "archived_deployments", from: "id", table: "archived_deployments_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_deployments, :archived_deployments_id_ks_idx, :id

    create_table :archived_issue_comments_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_issue_comments_id_ks_idx, :hash, :id

    create_vindex :archived_issue_comments_id_ks_idx, :lookup_unique, owner: "archived_issue_comments", from: "id", table: "archived_issue_comments_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_issue_comments, :archived_issue_comments_id_ks_idx, :id

    create_table :archived_issue_event_details_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_issue_event_details_id_ks_idx, :hash, :id

    create_vindex :archived_issue_event_details_id_ks_idx, :lookup_unique, owner: "archived_issue_event_details", from: "id", table: "archived_issue_event_details_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_issue_event_details, :archived_issue_event_details_id_ks_idx, :id

    create_table :archived_issue_events_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(11)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_issue_events_id_ks_idx, :hash, :id

    create_vindex :archived_issue_events_id_ks_idx, :lookup_unique, owner: "archived_issue_events", from: "id", table: "archived_issue_events_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_issue_events, :archived_issue_events_id_ks_idx, :id

    create_table :archived_issues_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_issues_id_ks_idx, :hash, :id

    create_vindex :archived_issues_id_ks_idx, :lookup_unique, owner: "archived_issues", from: "id", table: "archived_issues_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_issues, :archived_issues_id_ks_idx, :id

    create_table :archived_labels_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_labels_id_ks_idx, :hash, :id

    create_vindex :archived_labels_id_ks_idx, :lookup_unique, owner: "archived_labels", from: "id", table: "archived_labels_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_labels, :archived_labels_id_ks_idx, :id

    create_table :archived_milestones_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_milestones_id_ks_idx, :hash, :id

    create_vindex :archived_milestones_id_ks_idx, :lookup_unique, owner: "archived_milestones", from: "id", table: "archived_milestones_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_milestones, :archived_milestones_id_ks_idx, :id

    create_table :archived_pull_request_review_comments_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_pull_request_review_comments_id_ks_idx, :hash, :id

    create_vindex :archived_pull_request_review_comments_id_ks_idx, :lookup_unique, owner: "archived_pull_request_review_comments", from: "id", table: "archived_pull_request_review_comments_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_pull_request_review_comments, :archived_pull_request_review_comments_id_ks_idx, :id

    create_table :archived_pull_request_review_points_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_pull_request_review_points_id_ks_idx, :hash, :id

    create_vindex :archived_pull_request_review_points_id_ks_idx, :lookup_unique, owner: "archived_pull_request_review_points", from: "id", table: "archived_pull_request_review_points_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_pull_request_review_points, :archived_pull_request_review_points_id_ks_idx, :id

    create_table :archived_pull_request_review_threads_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_pull_request_review_threads_id_ks_idx, :hash, :id

    create_vindex :archived_pull_request_review_threads_id_ks_idx, :lookup_unique, owner: "archived_pull_request_review_threads", from: "id", table: "archived_pull_request_review_threads_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_pull_request_review_threads, :archived_pull_request_review_threads_id_ks_idx, :id

    create_table :archived_pull_request_reviews_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_pull_request_reviews_id_ks_idx, :hash, :id

    create_vindex :archived_pull_request_reviews_id_ks_idx, :lookup_unique, owner: "archived_pull_request_reviews", from: "id", table: "archived_pull_request_reviews_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_pull_request_reviews, :archived_pull_request_reviews_id_ks_idx, :id

    create_table :archived_pull_request_reviews_review_requests_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_pull_request_reviews_review_requests_id_ks_idx, :hash, :id

    create_vindex :archived_pull_request_reviews_review_requests_id_ks_idx, :lookup_unique, owner: "archived_pull_request_reviews_review_requests", from: "id", table: "archived_pull_request_reviews_review_requests_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_pull_request_reviews_review_requests, :archived_pull_request_reviews_review_requests_id_ks_idx, :id

    create_table :archived_pull_request_updates_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_pull_request_updates_id_ks_idx, :hash, :id

    create_vindex :archived_pull_request_updates_id_ks_idx, :lookup_unique, owner: "archived_pull_request_updates", from: "id", table: "archived_pull_request_updates_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_pull_request_updates, :archived_pull_request_updates_id_ks_idx, :id

    create_table :archived_pull_requests_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_pull_requests_id_ks_idx, :hash, :id

    create_vindex :archived_pull_requests_id_ks_idx, :lookup_unique, owner: "archived_pull_requests", from: "id", table: "archived_pull_requests_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_pull_requests, :archived_pull_requests_id_ks_idx, :id

    create_table :archived_review_request_reasons_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_review_request_reasons_id_ks_idx, :hash, :id

    create_vindex :archived_review_request_reasons_id_ks_idx, :lookup_unique, owner: "archived_review_request_reasons", from: "id", table: "archived_review_request_reasons_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_review_request_reasons, :archived_review_request_reasons_id_ks_idx, :id

    create_table :archived_review_requests_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :archived_review_requests_id_ks_idx, :hash, :id

    create_vindex :archived_review_requests_id_ks_idx, :lookup_unique, owner: "archived_review_requests", from: "id", table: "archived_review_requests_id_ks_idx", to: "keyspace_id"
    add_vindex :archived_review_requests, :archived_review_requests_id_ks_idx, :id

    create_table :assignments_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :assignments_id_ks_idx, :hash, :id

    create_vindex :assignments_id_ks_idx, :lookup_unique, owner: "assignments", from: "id", table: "assignments_id_ks_idx", to: "keyspace_id"
    add_vindex :assignments, :assignments_id_ks_idx, :id

    create_table :auto_merge_requests_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :auto_merge_requests_id_ks_idx, :hash, :id

    create_vindex :auto_merge_requests_id_ks_idx, :lookup_unique, owner: "auto_merge_requests", from: "id", table: "auto_merge_requests_id_ks_idx", to: "keyspace_id"
    add_vindex :auto_merge_requests, :auto_merge_requests_id_ks_idx, :id

    create_table :code_scanning_review_comments_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :code_scanning_review_comments_id_ks_idx, :hash, :id

    create_vindex :code_scanning_review_comments_id_ks_idx, :lookup_unique, owner: "code_scanning_review_comments", from: "id", table: "code_scanning_review_comments_id_ks_idx", to: "keyspace_id"
    add_vindex :code_scanning_review_comments, :code_scanning_review_comments_id_ks_idx, :id

    create_table :commit_comment_edits_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :commit_comment_edits_id_ks_idx, :hash, :id

    create_vindex :commit_comment_edits_id_ks_idx, :lookup_unique, owner: "commit_comment_edits", from: "id", table: "commit_comment_edits_id_ks_idx", to: "keyspace_id"
    add_vindex :commit_comment_edits, :commit_comment_edits_id_ks_idx, :id

    create_table :commit_comment_reactions_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :commit_comment_reactions_id_ks_idx, :hash, :id

    create_vindex :commit_comment_reactions_id_ks_idx, :lookup_unique, owner: "commit_comment_reactions", from: "id", table: "commit_comment_reactions_id_ks_idx", to: "keyspace_id"
    add_vindex :commit_comment_reactions, :commit_comment_reactions_id_ks_idx, :id

    create_table :commit_comments_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :commit_comments_id_ks_idx, :hash, :id

    create_vindex :commit_comments_id_ks_idx, :lookup_unique, owner: "commit_comments", from: "id", table: "commit_comments_id_ks_idx", to: "keyspace_id"
    add_vindex :commit_comments, :commit_comments_id_ks_idx, :id
    add_vindex :commit_comment_edits, :commit_comments_id_ks_idx, :commit_comment_id
    add_vindex :commit_comment_reactions, :commit_comments_id_ks_idx, :commit_comment_id

    create_table :commit_mentions_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :commit_mentions_id_ks_idx, :hash, :id

    create_vindex :commit_mentions_id_ks_idx, :lookup_unique, owner: "commit_mentions", from: "id", table: "commit_mentions_id_ks_idx", to: "keyspace_id"
    add_vindex :commit_mentions, :commit_mentions_id_ks_idx, :id

    create_table :cross_references_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :cross_references_id_ks_idx, :hash, :id

    create_vindex :cross_references_id_ks_idx, :lookup_unique, owner: "cross_references", from: "id", table: "cross_references_id_ks_idx", to: "keyspace_id"
    add_vindex :cross_references, :cross_references_id_ks_idx, :id

    create_table :deployment_statuses_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :deployment_statuses_id_ks_idx, :hash, :id

    create_vindex :deployment_statuses_id_ks_idx, :lookup_unique, owner: "deployment_statuses", from: "id", table: "deployment_statuses_id_ks_idx", to: "keyspace_id"
    add_vindex :deployment_statuses, :deployment_statuses_id_ks_idx, :id
    add_vindex :deployments, :deployment_statuses_id_ks_idx, :latest_deployment_status_id

    create_table :deployments_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :deployments_id_ks_idx, :hash, :id

    create_vindex :deployments_id_ks_idx, :lookup_unique, owner: "deployments", from: "id", table: "deployments_id_ks_idx", to: "keyspace_id"
    add_vindex :deployments, :deployments_id_ks_idx, :id
    add_vindex :deployment_statuses, :deployments_id_ks_idx, :deployment_id

    create_table :duplicate_issues_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :duplicate_issues_id_ks_idx, :hash, :id

    create_vindex :duplicate_issues_id_ks_idx, :lookup_unique, owner: "duplicate_issues", from: "id", table: "duplicate_issues_id_ks_idx", to: "keyspace_id"
    add_vindex :duplicate_issues, :duplicate_issues_id_ks_idx, :id

    create_table :issue_alert_links_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_alert_links_id_ks_idx, :hash, :id

    create_vindex :issue_alert_links_id_ks_idx, :lookup_unique, owner: "issue_alert_links", from: "id", table: "issue_alert_links_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_alert_links, :issue_alert_links_id_ks_idx, :id

    create_table :issue_blob_references_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_blob_references_id_ks_idx, :hash, :id

    create_vindex :issue_blob_references_id_ks_idx, :lookup_unique, owner: "issue_blob_references", from: "id", table: "issue_blob_references_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_blob_references, :issue_blob_references_id_ks_idx, :id

    create_table :issue_comment_edits_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_comment_edits_id_ks_idx, :hash, :id

    create_vindex :issue_comment_edits_id_ks_idx, :lookup_unique, owner: "issue_comment_edits", from: "id", table: "issue_comment_edits_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_comment_edits, :issue_comment_edits_id_ks_idx, :id

    create_table :issue_comment_meta_data_blobs_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_comment_meta_data_blobs_id_ks_idx, :hash, :id

    create_vindex :issue_comment_meta_data_blobs_id_ks_idx, :lookup_unique, owner: "issue_comment_meta_data_blobs", from: "id", table: "issue_comment_meta_data_blobs_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_comment_meta_data_blobs, :issue_comment_meta_data_blobs_id_ks_idx, :id

    create_table :issue_comment_reactions_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_comment_reactions_id_ks_idx, :hash, :id

    create_vindex :issue_comment_reactions_id_ks_idx, :lookup_unique, owner: "issue_comment_reactions", from: "id", table: "issue_comment_reactions_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_comment_reactions, :issue_comment_reactions_id_ks_idx, :id

    create_table :issue_comments_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_comments_id_ks_idx, :hash, :id

    create_vindex :issue_comments_id_ks_idx, :lookup_unique, owner: "issue_comments", from: "id", table: "issue_comments_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_comments, :issue_comments_id_ks_idx, :id
    add_vindex :issue_comment_edits, :issue_comments_id_ks_idx, :issue_comment_id
    add_vindex :issue_comment_meta_data_blobs, :issue_comments_id_ks_idx, :issue_comment_id
    add_vindex :issue_comment_reactions, :issue_comments_id_ks_idx, :issue_comment_id

    create_table :issue_edits_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_edits_id_ks_idx, :hash, :id

    create_vindex :issue_edits_id_ks_idx, :lookup_unique, owner: "issue_edits", from: "id", table: "issue_edits_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_edits, :issue_edits_id_ks_idx, :id

    create_table :issue_event_details_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_event_details_id_ks_idx, :hash, :id

    create_vindex :issue_event_details_id_ks_idx, :lookup_unique, owner: "issue_event_details", from: "id", table: "issue_event_details_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_event_details, :issue_event_details_id_ks_idx, :id

    create_table :issue_events_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(11)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_events_id_ks_idx, :hash, :id

    create_vindex :issue_events_id_ks_idx, :lookup_unique, owner: "issue_events", from: "id", table: "issue_events_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_events, :issue_events_id_ks_idx, :id
    add_vindex :issue_event_details, :issue_events_id_ks_idx, :issue_event_id

    create_table :issue_imports_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_imports_id_ks_idx, :hash, :id

    create_vindex :issue_imports_id_ks_idx, :lookup_unique, owner: "issue_imports", from: "id", table: "issue_imports_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_imports, :issue_imports_id_ks_idx, :id

    create_table :issue_links_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_links_id_ks_idx, :hash, :id

    create_vindex :issue_links_id_ks_idx, :lookup_unique, owner: "issue_links", from: "id", table: "issue_links_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_links, :issue_links_id_ks_idx, :id

    create_table :issue_priorities_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_priorities_id_ks_idx, :hash, :id

    create_vindex :issue_priorities_id_ks_idx, :lookup_unique, owner: "issue_priorities", from: "id", table: "issue_priorities_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_priorities, :issue_priorities_id_ks_idx, :id

    create_table :issue_reactions_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_reactions_id_ks_idx, :hash, :id

    create_vindex :issue_reactions_id_ks_idx, :lookup_unique, owner: "issue_reactions", from: "id", table: "issue_reactions_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_reactions, :issue_reactions_id_ks_idx, :id

    create_table :issues_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issues_id_ks_idx, :hash, :id

    create_vindex :issues_id_ks_idx, :lookup_unique, owner: "issues", from: "id", table: "issues_id_ks_idx", to: "keyspace_id"
    add_vindex :issues, :issues_id_ks_idx, :id
    add_vindex :assignments, :issues_id_ks_idx, :issue_id
    add_vindex :duplicate_issues, :issues_id_ks_idx, :issue_id
    add_vindex :issue_blob_references, :issues_id_ks_idx, :issue_id
    add_vindex :issue_comments, :issues_id_ks_idx, :issue_id
    add_vindex :issue_edits, :issues_id_ks_idx, :issue_id
    add_vindex :issue_events, :issues_id_ks_idx, :issue_id
    add_vindex :issue_links, :issues_id_ks_idx, :source_issue_id
    add_vindex :issue_priorities, :issues_id_ks_idx, :issue_id
    add_vindex :issue_reactions, :issues_id_ks_idx, :issue_id
    add_vindex :issues_labels, :issues_id_ks_idx, :issue_id

    create_table :issues_labels_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issues_labels_id_ks_idx, :hash, :id

    create_vindex :issues_labels_id_ks_idx, :lookup_unique, owner: "issues_labels", from: "id", table: "issues_labels_id_ks_idx", to: "keyspace_id"
    add_vindex :issues_labels, :issues_labels_id_ks_idx, :id

    create_table :labels_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :labels_id_ks_idx, :hash, :id

    create_vindex :labels_id_ks_idx, :lookup_unique, owner: "labels", from: "id", table: "labels_id_ks_idx", to: "keyspace_id"
    add_vindex :labels, :labels_id_ks_idx, :id
    add_vindex :issues_labels, :labels_id_ks_idx, :label_id

    create_table :last_seen_pull_request_revisions_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :last_seen_pull_request_revisions_id_ks_idx, :hash, :id

    create_vindex :last_seen_pull_request_revisions_id_ks_idx, :lookup_unique, owner: "last_seen_pull_request_revisions", from: "id", table: "last_seen_pull_request_revisions_id_ks_idx", to: "keyspace_id"
    add_vindex :last_seen_pull_request_revisions, :last_seen_pull_request_revisions_id_ks_idx, :id

    create_table :milestones_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :milestones_id_ks_idx, :hash, :id

    create_vindex :milestones_id_ks_idx, :lookup_unique, owner: "milestones", from: "id", table: "milestones_id_ks_idx", to: "keyspace_id"
    add_vindex :milestones, :milestones_id_ks_idx, :id
    add_vindex :issue_priorities, :milestones_id_ks_idx, :milestone_id
    add_vindex :issues, :milestones_id_ks_idx, :milestone_id

    create_table :pull_request_conflicts_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_conflicts_id_ks_idx, :hash, :id

    create_vindex :pull_request_conflicts_id_ks_idx, :lookup_unique, owner: "pull_request_conflicts", from: "id", table: "pull_request_conflicts_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_request_conflicts, :pull_request_conflicts_id_ks_idx, :id

    create_table :pull_request_review_comment_edits_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_review_comment_edits_id_ks_idx, :hash, :id

    create_vindex :pull_request_review_comment_edits_id_ks_idx, :lookup_unique, owner: "pull_request_review_comment_edits", from: "id", table: "pull_request_review_comment_edits_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_request_review_comment_edits, :pull_request_review_comment_edits_id_ks_idx, :id

    create_table :pull_request_review_comment_reactions_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_review_comment_reactions_id_ks_idx, :hash, :id

    create_vindex :pull_request_review_comment_reactions_id_ks_idx, :lookup_unique, owner: "pull_request_review_comment_reactions", from: "id", table: "pull_request_review_comment_reactions_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_request_review_comment_reactions, :pull_request_review_comment_reactions_id_ks_idx, :id

    create_table :pull_request_review_comments_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_review_comments_id_ks_idx, :hash, :id

    create_vindex :pull_request_review_comments_id_ks_idx, :lookup_unique, owner: "pull_request_review_comments", from: "id", table: "pull_request_review_comments_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_request_review_comments, :pull_request_review_comments_id_ks_idx, :id
    add_vindex :code_scanning_review_comments, :pull_request_review_comments_id_ks_idx, :pull_request_review_comment_id
    add_vindex :pull_request_review_comment_edits, :pull_request_review_comments_id_ks_idx, :pull_request_review_comment_id
    add_vindex :pull_request_review_comment_reactions, :pull_request_review_comments_id_ks_idx, :pull_request_review_comment_id

    create_table :pull_request_review_edits_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_review_edits_id_ks_idx, :hash, :id

    create_vindex :pull_request_review_edits_id_ks_idx, :lookup_unique, owner: "pull_request_review_edits", from: "id", table: "pull_request_review_edits_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_request_review_edits, :pull_request_review_edits_id_ks_idx, :id

    create_table :pull_request_review_points_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_review_points_id_ks_idx, :hash, :id

    create_vindex :pull_request_review_points_id_ks_idx, :lookup_unique, owner: "pull_request_review_points", from: "id", table: "pull_request_review_points_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_request_review_points, :pull_request_review_points_id_ks_idx, :id

    create_table :pull_request_review_reactions_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_review_reactions_id_ks_idx, :hash, :id

    create_vindex :pull_request_review_reactions_id_ks_idx, :lookup_unique, owner: "pull_request_review_reactions", from: "id", table: "pull_request_review_reactions_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_request_review_reactions, :pull_request_review_reactions_id_ks_idx, :id

    create_table :pull_request_review_threads_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_review_threads_id_ks_idx, :hash, :id

    create_vindex :pull_request_review_threads_id_ks_idx, :lookup_unique, owner: "pull_request_review_threads", from: "id", table: "pull_request_review_threads_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_request_review_threads, :pull_request_review_threads_id_ks_idx, :id
    add_vindex :pull_request_review_comments, :pull_request_review_threads_id_ks_idx, :pull_request_review_thread_id

    create_table :pull_request_reviews_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_reviews_id_ks_idx, :hash, :id

    create_vindex :pull_request_reviews_id_ks_idx, :lookup_unique, owner: "pull_request_reviews", from: "id", table: "pull_request_reviews_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_request_reviews, :pull_request_reviews_id_ks_idx, :id
    add_vindex :pull_request_review_comments, :pull_request_reviews_id_ks_idx, :pull_request_review_id
    add_vindex :pull_request_review_edits, :pull_request_reviews_id_ks_idx, :pull_request_review_id
    add_vindex :pull_request_review_reactions, :pull_request_reviews_id_ks_idx, :pull_request_review_id
    add_vindex :pull_request_review_threads, :pull_request_reviews_id_ks_idx, :pull_request_review_id
    add_vindex :pull_request_reviews_review_requests, :pull_request_reviews_id_ks_idx, :pull_request_review_id

    create_table :pull_request_reviews_review_requests_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_reviews_review_requests_id_ks_idx, :hash, :id

    create_vindex :pull_request_reviews_review_requests_id_ks_idx, :lookup_unique, owner: "pull_request_reviews_review_requests", from: "id", table: "pull_request_reviews_review_requests_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_request_reviews_review_requests, :pull_request_reviews_review_requests_id_ks_idx, :id

    create_table :pull_request_sources_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_sources_id_ks_idx, :hash, :id

    create_vindex :pull_request_sources_id_ks_idx, :lookup_unique, owner: "pull_request_sources", from: "id", table: "pull_request_sources_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_request_sources, :pull_request_sources_id_ks_idx, :id

    create_table :pull_request_updates_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_request_updates_id_ks_idx, :hash, :id

    create_vindex :pull_request_updates_id_ks_idx, :lookup_unique, owner: "pull_request_updates", from: "id", table: "pull_request_updates_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_request_updates, :pull_request_updates_id_ks_idx, :id
    add_vindex :pull_request_review_points, :pull_request_updates_id_ks_idx, :pull_request_update_id

    create_table :pull_requests_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "int(11)", primary_key: true, auto_increment: false, unsigned: false, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :pull_requests_id_ks_idx, :hash, :id

    create_vindex :pull_requests_id_ks_idx, :lookup_unique, owner: "pull_requests", from: "id", table: "pull_requests_id_ks_idx", to: "keyspace_id"
    add_vindex :pull_requests, :pull_requests_id_ks_idx, :id
    add_vindex :auto_merge_requests, :pull_requests_id_ks_idx, :pull_request_id
    add_vindex :issues, :pull_requests_id_ks_idx, :pull_request_id
    add_vindex :last_seen_pull_request_revisions, :pull_requests_id_ks_idx, :pull_request_id
    add_vindex :pull_request_conflicts, :pull_requests_id_ks_idx, :pull_request_id
    add_vindex :pull_request_review_comments, :pull_requests_id_ks_idx, :pull_request_id
    add_vindex :pull_request_review_points, :pull_requests_id_ks_idx, :pull_request_id
    add_vindex :pull_request_review_threads, :pull_requests_id_ks_idx, :pull_request_id
    add_vindex :pull_request_reviews, :pull_requests_id_ks_idx, :pull_request_id
    add_vindex :pull_request_sources, :pull_requests_id_ks_idx, :pull_request_id
    add_vindex :pull_request_updates, :pull_requests_id_ks_idx, :pull_request_id
    add_vindex :review_requests, :pull_requests_id_ks_idx, :pull_request_id

    create_table :repository_milestones_sequences_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :repository_milestones_sequences_id_ks_idx, :hash, :id

    create_vindex :repository_milestones_sequences_id_ks_idx, :lookup_unique, owner: "repository_milestones_sequences", from: "id", table: "repository_milestones_sequences_id_ks_idx", to: "keyspace_id"
    add_vindex :repository_milestones_sequences, :repository_milestones_sequences_id_ks_idx, :id

    create_table :repository_properties_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :repository_properties_id_ks_idx, :hash, :id

    create_vindex :repository_properties_id_ks_idx, :lookup_unique, owner: "repository_properties", from: "id", table: "repository_properties_id_ks_idx", to: "keyspace_id"
    add_vindex :repository_properties, :repository_properties_id_ks_idx, :id

    create_table :review_request_reasons_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :review_request_reasons_id_ks_idx, :hash, :id

    create_vindex :review_request_reasons_id_ks_idx, :lookup_unique, owner: "review_request_reasons", from: "id", table: "review_request_reasons_id_ks_idx", to: "keyspace_id"
    add_vindex :review_request_reasons, :review_request_reasons_id_ks_idx, :id

    create_table :review_requests_id_ks_idx, id: false, charset: "utf8", collation: "utf8_general_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :review_requests_id_ks_idx, :hash, :id

    create_vindex :review_requests_id_ks_idx, :lookup_unique, owner: "review_requests", from: "id", table: "review_requests_id_ks_idx", to: "keyspace_id"
    add_vindex :review_requests, :review_requests_id_ks_idx, :id
    add_vindex :pull_request_reviews_review_requests, :review_requests_id_ks_idx, :review_request_id
    add_vindex :review_request_reasons, :review_requests_id_ks_idx, :review_request_id
  end
end
