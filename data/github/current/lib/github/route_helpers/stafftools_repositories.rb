# typed: false
# frozen_string_literal: true

module GitHub
  module RouteHelpers

    # GETs
    def gh_stafftools_repository_path(repo)
      expand_nwo_from :stafftools_repository_path, repo
    end

    def gh_overview_stafftools_repository_path(repo)
      expand_nwo_from :overview_stafftools_repository_path, repo
    end

    def gh_admin_stafftools_repository_path(repo)
      expand_nwo_from :admin_stafftools_repository_path, repo
    end

    def gh_stafftools_repository_vulnerability_alerts_path(repo)
      expand_nwo_from :stafftools_repository_vulnerability_alerts_path, repo
    end

    def gh_collaboration_stafftools_repository_path(repo)
      expand_nwo_from :collaboration_stafftools_repository_path, repo
    end

    def gh_permissions_stafftools_repository_path(repo)
      expand_nwo_from :permissions_stafftools_repository_path, repo
    end

    def gh_stafftools_repository_collaborators_path(repo)
      expand_nwo_from :stafftools_repository_collaborators_path, repo
    end

    def gh_stafftools_repository_notification_settings_path(repo)
      expand_nwo_from :stafftools_repository_notification_settings_path, repo
    end

    def gh_stafftools_repo_hooks_path(repo)
      expand_nwo_from :stafftools_repo_hooks_path, repo
    end

    def gh_database_stafftools_repository_path(repo)
      expand_nwo_from :database_stafftools_repository_path, repo
    end

    def gh_deploy_keys_stafftools_repository_path(repo)
      expand_nwo_from :deploy_keys_stafftools_repository_path, repo
    end

    def gh_disk_stafftools_repository_path(repo)
      expand_nwo_from :disk_stafftools_repository_path, repo
    end

    def gh_events_stafftools_repository_path(repo)
      expand_nwo_from :events_stafftools_repository_path, repo
    end

    def gh_fsck_stafftools_repository_path(repo)
      expand_nwo_from :fsck_stafftools_repository_path, repo
    end

    def gh_abuse_reports_stafftools_repository_path(repo)
      expand_nwo_from :abuse_reports_stafftools_repository_path, repo
    end

    def gh_reflog_sync_stafftools_repository_path(repo)
      expand_nwo_from :reflog_sync_stafftools_repository_path, repo
    end

    def gh_languages_stafftools_repository_path(repo)
      expand_nwo_from :languages_stafftools_repository_path, repo
    end

    def gh_network_map_stafftools_repository_path(repo)
      expand_nwo_from :network_map_stafftools_repository_path, repo
    end

    def gh_releases_stafftools_repository_path(repo)
      expand_nwo_from :releases_stafftools_repository_path, repo
    end

    def gh_unpublish_unsearchable_releases_stafftools_repository_path(repo, options = nil)
      unpublish_unsearchable_releases_stafftools_repository_path(repo.owner, repo, options)
    end

    def gh_stafftools_repository_network_path(repo)
      expand_nwo_from :stafftools_repository_network_path, repo
    end

    def gh_stafftools_repository_network_tree_path(repo)
      expand_nwo_from :stafftools_repository_network_tree_path, repo
    end

    def gh_siblings_stafftools_repository_network_path(repo)
      expand_nwo_from :siblings_stafftools_repository_network_path, repo
    end

    def gh_children_stafftools_repository_network_path(repo)
      expand_nwo_from :children_stafftools_repository_network_path, repo
    end

    def gh_stafftools_repository_issues_path(repo)
      expand_nwo_from :stafftools_repository_issues_path, repo
    end

    def gh_stafftools_repository_watchers_path(repo)
      expand_nwo_from :stafftools_repository_watchers_path, repo
    end

    def gh_notifications_stafftools_repository_path(repo)
      expand_nwo_from :notifications_stafftools_repository_path, repo
    end

    def gh_stafftools_repository_projects_path(repo)
      expand_nwo_from :stafftools_repository_projects_path, repo
    end

    def gh_search_stafftools_repository_path(repo)
      expand_nwo_from :search_stafftools_repository_path, repo
    end

    def gh_security_stafftools_repository_path(repo)
      expand_nwo_from :security_stafftools_repository_path, repo
    end

    def gh_stafftools_repository_large_files_path(repo, options = nil)
      stafftools_repository_large_files_path(repo.owner, repo, options)
    end

    def gh_preview_stafftools_repository_large_files_path(repo)
      expand_nwo_from :preview_stafftools_repository_large_files_path, repo
    end

    def gh_change_timeout_stafftools_repository_large_files_path(repo)
      expand_nwo_from :change_timeout_stafftools_repository_large_files_path, repo
    end

    def gh_archive_stafftools_repository_large_file_path(repo, id)
      archive_stafftools_repository_large_file_path(repo.owner, repo, id)
    end

    def gh_unarchive_stafftools_repository_large_file_path(repo, id)
      unarchive_stafftools_repository_large_file_path(repo.owner, repo, id)
    end

    def gh_stafftools_repository_protected_branches_path(repo)
      expand_nwo_from :stafftools_repository_protected_branches_path, repo
    end

    def gh_status_stafftools_repository_pages_path(repo)
      expand_nwo_from :status_stafftools_repository_pages_path, repo
    end

    def gh_https_status_stafftools_repository_pages_path(repo)
      expand_nwo_from :https_status_stafftools_repository_pages_path, repo
    end

    def gh_unlock_build_stafftools_repository_pages_path(repo)
      expand_nwo_from :unlock_build_stafftools_repository_pages_path, repo
    end

    def gh_dependency_graph_stafftools_repository_path(repo)
      expand_nwo_from :dependency_graph_stafftools_repository_path, repo
    end

    def gh_dependabot_stafftools_repository_path(repo)
      expand_nwo_from :stafftools_repository_dependabot_path, repo
    end

    def gh_actions_stafftools_repository_path(repo)
      expand_nwo_from :actions_stafftools_repository_path, repo
    end

    def gh_actions_workflows_stafftools_repository_path(repo)
      expand_nwo_from :actions_workflows_stafftools_repository_path, repo
    end

    def gh_actions_billing_stafftools_repository_path(repo)
      expand_nwo_from :actions_billing_stafftools_repository_path, repo
    end

    def gh_actions_latest_runs_stafftools_repository_path(repo)
      expand_nwo_from :actions_latest_runs_stafftools_repository_path, repo
    end

    def gh_actions_self_hosted_runners_stafftools_repository_path(repo)
      expand_nwo_from :actions_self_hosted_runners_stafftools_repository_path, repo
    end

    def gh_actions_secrets_stafftools_repository_path(repo)
      expand_nwo_from :actions_secrets_stafftools_repository_path, repo
    end

    def gh_actions_variables_stafftools_repository_path(repo)
      expand_nwo_from :actions_variables_stafftools_repository_path, repo
    end

    def gh_actions_pull_requests_stafftools_repository_path(repo)
      expand_nwo_from :actions_pull_requests_stafftools_repository_path, repo
    end

    def gh_actions_pull_request_stafftools_repository_path(pr)
      actions_pull_request_stafftools_repository_path(pr.repository.owner, pr.repository, pr.id)
    end

    def gh_actions_pull_request_commit_stafftools_repository_path(repo, pull_request_id, sha)
      actions_pull_request_commit_stafftools_repository_path(repo.owner, repo, pull_request_id, sha)
    end

    def gh_commit_statuses_sha_summary_stafftools_repository_path(repo, sha)
      commit_statuses_sha_summary_stafftools_repository_path(repo.owner, repo, sha)
    end

    # POSTs
    def gh_admin_disable_stafftools_repository_path(repo)
      expand_nwo_from :admin_disable_stafftools_repository_path, repo
    end

    def gh_analyze_language_stafftools_repository_path(repo)
      expand_nwo_from :analyze_language_stafftools_repository_path, repo
    end

    def gh_change_allow_force_push_stafftools_repository_path(repo)
      expand_nwo_from :change_allow_force_push_stafftools_repository_path, repo
    end

    def gh_change_max_object_size_stafftools_repository_path(repo)
      expand_nwo_from :change_max_object_size_stafftools_repository_path, repo
    end

    def gh_change_disk_quota_stafftools_repository_path(kind, repo)
      case kind
      when :warn
        expand_nwo_from :change_warn_disk_quota_stafftools_repository_path, repo
      when :lock
        expand_nwo_from :change_lock_disk_quota_stafftools_repository_path, repo
      end
    end

    def gh_funding_links_disable_stafftools_repository_path(repo)
      expand_nwo_from :funding_links_disable_stafftools_repository_path, repo
    end

    def gh_lock_stafftools_repository_path(repo)
      expand_nwo_from :lock_stafftools_repository_path, repo
    end

    def gh_hide_from_google_stafftools_repository_path(repo)
      expand_nwo_from :hide_from_google_stafftools_repository_path, repo
    end

    def gh_require_login_stafftools_repository_path(repo)
      expand_nwo_from :require_login_stafftools_repository_path, repo
    end

    def gh_content_warning_stafftools_repository_path(repo)
      expand_nwo_from :content_warning_stafftools_repository_path, repo
    end

    def gh_require_opt_in_stafftools_repository_path(repo)
      expand_nwo_from :require_opt_in_stafftools_repository_path, repo
    end

    def gh_require_opt_in_on_entire_network_stafftools_repository_path(repo)
      expand_nwo_from :require_opt_in_on_entire_network_stafftools_repository_path, repo
    end

    def gh_collaborators_only_stafftools_repository_path(repo)
      expand_nwo_from :collaborators_only_stafftools_repository_path, repo
    end

    def gh_lock_for_migration_stafftools_repository_path(repo)
      expand_nwo_from :lock_for_migration_stafftools_repository_path, repo
    end

    def gh_purge_code_stafftools_repository_path(repo)
      expand_nwo_from :purge_code_stafftools_repository_path, repo
    end

    def gh_purge_commits_stafftools_repository_path(repo)
      expand_nwo_from :purge_commits_stafftools_repository_path, repo
    end

    def gh_purge_issues_stafftools_repository_path(repo)
      expand_nwo_from :purge_issues_stafftools_repository_path, repo
    end

    def gh_purge_projects_stafftools_repository_path(repo)
      expand_nwo_from :purge_projects_stafftools_repository_path, repo
    end

    def gh_purge_releases_stafftools_repository_path(repo)
      expand_nwo_from :purge_releases_stafftools_repository_path, repo
    end

    def gh_purge_discussions_stafftools_repository_path(repo)
      expand_nwo_from :purge_discussions_stafftools_repository_path, repo
    end

    def gh_purge_dependabot_alerts_stafftools_repository_path(repo)
      expand_nwo_from :purge_dependabot_alerts_stafftools_repository_path, repo
    end

    def gh_purge_repository_stafftools_repository_path(repo)
      expand_nwo_from :purge_repository_stafftools_repository_path, repo
    end

    def gh_purge_wiki_stafftools_repository_path(repo)
      expand_nwo_from :purge_wiki_stafftools_repository_path, repo
    end

    def gh_rebuild_commit_contributions_stafftools_repository_path(repo)
      expand_nwo_from :rebuild_commit_contributions_stafftools_repository_path, repo
    end

    def gh_reindex_code_stafftools_repository_path(repo)
      expand_nwo_from :reindex_code_stafftools_repository_path, repo
    end

    def gh_reindex_blackbird_stafftools_repository_path(repo)
      expand_nwo_from :reindex_blackbird_stafftools_repository_path, repo
    end

    def gh_reindex_blackbird_embeddings_stafftools_repository_path(repo)
      expand_nwo_from :reindex_blackbird_embeddings_stafftools_repository_path, repo
    end

    def gh_enable_code_search_stafftools_repository_path(repo)
      expand_nwo_from :enable_code_search_stafftools_repository_path, repo
    end

    def gh_reindex_commits_stafftools_repository_path(repo)
      expand_nwo_from :reindex_commits_stafftools_repository_path, repo
    end

    def gh_reindex_issues_stafftools_repository_path(repo)
      expand_nwo_from :reindex_issues_stafftools_repository_path, repo
    end

    def gh_reindex_projects_stafftools_repository_path(repo)
      expand_nwo_from :reindex_projects_stafftools_repository_path, repo
    end

    def gh_reindex_discussions_stafftools_repository_path(repo)
      expand_nwo_from :reindex_discussions_stafftools_repository_path, repo
    end

    def gh_reindex_dependabot_alerts_stafftools_repository_path(repo)
      expand_nwo_from :reindex_dependabot_alerts_stafftools_repository_path, repo
    end

    def gh_reindex_releases_stafftools_repository_path(repo)
      expand_nwo_from :reindex_releases_stafftools_repository_path, repo
    end

    def gh_reindex_repository_stafftools_repository_path(repo)
      expand_nwo_from :reindex_repository_stafftools_repository_path, repo
    end

    def gh_reindex_wiki_stafftools_repository_path(repo)
      expand_nwo_from :reindex_wiki_stafftools_repository_path, repo
    end

    def gh_request_access_stafftools_repository_path(repo)
      expand_nwo_from :request_access_stafftools_repository_path, repo
    end

    def gh_staff_override_unlock_stafftools_repository_path(repo)
      expand_nwo_from :staff_override_unlock_stafftools_repository_path, repo
    end

    def gh_staff_unlock_stafftools_repository_path(repo)
      expand_nwo_from :staff_unlock_stafftools_repository_path, repo
    end

    def gh_size_disable_stafftools_repository_path(repo)
      expand_nwo_from :size_disable_stafftools_repository_path, repo
    end

    def gh_toggle_allow_git_graph_stafftools_repository_path(repo)
      expand_nwo_from :toggle_allow_git_graph_stafftools_repository_path, repo
    end

    def gh_toggle_token_scanning_stafftools_repository_path(repo)
      expand_nwo_from :toggle_token_scanning_stafftools_repository_path, repo
    end

    def gh_toggle_generic_secret_scanning_stafftools_repository_path(repo)
      expand_nwo_from :toggle_generic_secret_scanning_stafftools_repository_path, repo
    end

    def gh_toggle_permission_stafftools_repository_path(repo)
      expand_nwo_from :toggle_permission_stafftools_repository_path, repo
    end

    def gh_toggle_public_push_stafftools_repository_path(repo)
      expand_nwo_from :toggle_public_push_stafftools_repository_path, repo
    end

    def gh_transfer_stafftools_repository_path(repo)
      expand_nwo_from :transfer_stafftools_repository_path, repo
    end

    def gh_unlock_stafftools_repository_path(repo)
      expand_nwo_from :unlock_stafftools_repository_path, repo
    end

    def gh_wiki_mark_as_broken_stafftools_repository_path(repo)
      expand_nwo_from :wiki_mark_as_broken_stafftools_repository_path, repo
    end

    def gh_wiki_restore_stafftools_repository_path(repo)
      expand_nwo_from :wiki_restore_stafftools_repository_path, repo
    end

    def gh_wiki_schedule_maintenance_stafftools_repository_path(repo)
      expand_nwo_from :wiki_schedule_maintenance_stafftools_repository_path, repo
    end

    def gh_redetect_license_stafftools_repository_path(repo)
      expand_nwo_from :redetect_license_stafftools_repository_path, repo
    end

    def gh_pause_repo_invite_limit_stafftools_repository_path(repo)
      expand_nwo_from :pause_repo_invite_limit_stafftools_repository_path, repo
    end

    def gh_schedule_backup_stafftools_repository_path(repo)
      expand_nwo_from :schedule_backup_stafftools_repository_path, repo
    end

    def gh_schedule_wiki_backup_stafftools_repository_path(repo)
      expand_nwo_from :schedule_wiki_backup_stafftools_repository_path, repo
    end

    def gh_detect_manifests_stafftools_repository_path(repo)
      expand_nwo_from :detect_manifests_stafftools_repository_path, repo
    end

    def gh_clear_dependencies_stafftools_repository_path(repo)
      expand_nwo_from :clear_dependencies_stafftools_repository_path, repo
    end

    def gh_clear_snapshot_dependencies_stafftools_repository_path(repo)
      expand_nwo_from :clear_snapshot_dependencies_stafftools_repository_path, repo
    end

    def gh_download_dependency_snapshot_stafftools_repository_path(repo, snapshot_id)
      base = expand_nwo_from :download_dependency_snapshot_stafftools_repository_path, repo
      "#{base}?snapshot_id=#{snapshot_id}"
    end

    def gh_exclude_dependency_snapshot_stafftools_repository_path(repo, snapshot_id)
      base = expand_nwo_from :exclude_dependency_snapshot_stafftools_repository_path, repo
      "#{base}?snapshot_id=#{snapshot_id}"
    end

    def gh_archive_stafftools_repository_path(repo)
      expand_nwo_from :archive_stafftools_repository_path, repo
    end

    def gh_unarchive_stafftools_repository_path(repo)
      expand_nwo_from :unarchive_stafftools_repository_path, repo
    end

    def gh_set_used_by_stafftools_repository_path(repo)
      expand_nwo_from :set_used_by_stafftools_repository_path, repo
    end

    # PUTs
    def gh_clear_generated_pages_stafftools_repository_pages_path(repo)
      expand_nwo_from :clear_generated_pages_stafftools_repository_pages_path, repo
    end

    def gh_clear_domain_stafftools_repository_pages_path(repo)
      expand_nwo_from :clear_domain_stafftools_repository_pages_path, repo
    end

    def gh_request_https_certificate_stafftools_repository_pages_path(repo)
      expand_nwo_from :request_https_certificate_stafftools_repository_pages_path, repo
    end

    def gh_delete_https_certificate_stafftools_repository_pages_path(repo)
      expand_nwo_from :delete_https_certificate_stafftools_repository_pages_path, repo
    end

    def gh_restore_page_stafftools_repository_pages_path(repo)
      expand_nwo_from :restore_page_stafftools_repository_pages_path, repo
    end

    # DELETEs
    def gh_cancel_access_request_stafftools_repository_path(repo)
      expand_nwo_from :cancel_access_request_stafftools_repository_path, repo
    end

    def gh_cancel_unlock_stafftools_repository_path(repo)
      expand_nwo_from :cancel_unlock_stafftools_repository_path, repo
    end

    def gh_disable_stafftools_repository_path(repo)
      expand_nwo_from :disable_stafftools_repository_path, repo
    end

    def gh_purge_events_stafftools_repository_path(repo)
      expand_nwo_from :purge_events_stafftools_repository_path, repo
    end

    def gh_toggle_anonymous_release_download_stafftools_repository_path(repo)
      expand_nwo_from :toggle_anonymous_release_download_stafftools_repository_path, repo
    end
  end
end
