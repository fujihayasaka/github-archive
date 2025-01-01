# typed: true
# frozen_string_literal: true

module GitHub
  module DatabaseStructure

    CONFIGURATIONS_TABLES = [
      "configuration_entries"
    ]

    IAM_ABILITIES_TABLES = %w[
      abilities
      fine_grained_permissions
      roles
      role_permissions
      user_roles
    ]

    MYSQL2_TABLES = %w[
      custom_inboxes
      hidden_users
      notification_key_values
      notification_subscriptions
      notification_thread_subscriptions
      notification_thread_type_subscriptions
      notification_subscription_events
      notification_user_settings
      mobile_push_notification_schedules
      mobile_push_notification_settings
    ]

    NOTIFICATIONS_DELIVERIES_TABLES = %w[]

    NOTIFICATIONS_ENTRIES_TABLES = %w[
      notification_entries
      spammy_notification_entries
      saved_notification_entries
    ]

    NOTIFICATIONS_SUMMARIES_TABLES = %w[
      notification_summaries
    ]

    MYSQL5_TABLES = %w[
      key_values
      stratocaster_indexes
      search_index_template_configurations
      global_stratocaster_indexes
    ]

    VT_TABLES = [
      "actions_key_values_id_seq",
      "artifacts_id_seq",
      "check_annotations_id_seq",
      "check_runs_id_seq",
      "check_steps_id_seq",
      "check_suites_id_seq",
      "code_scanning_alert_links_id_seq",
      "code_scanning_alerts_id_seq",
      "code_scanning_check_suites_id_seq",
      "commit_rollups_id_seq",
      "statuses_id_seq",
      "workflow_job_runs_id_seq",
      "workflow_run_executions_id_seq",
      "workflow_runs_id_seq",
      "workflows_id_seq",
      "actions_cache_usages_id_seq",
      "archived_assignments_id_seq", # issues-pull-requests start
      "archived_commit_comments_id_seq",
      "archived_deployment_statuses_id_seq",
      "archived_deployments_id_seq",
      "archived_issue_comments_id_seq",
      "archived_issue_event_details_id_seq",
      "archived_issue_events_id_seq",
      "archived_issues_id_seq",
      "archived_labels_id_seq",
      "archived_milestones_id_seq",
      "archived_pull_request_review_comments_id_seq",
      "archived_pull_request_review_points_id_seq",
      "archived_pull_request_review_threads_id_seq",
      "archived_pull_request_reviews_id_seq",
      "archived_pull_request_reviews_review_requests_id_seq",
      "archived_pull_request_updates_id_seq",
      "archived_pull_requests_id_seq",
      "archived_review_request_reasons_id_seq",
      "archived_review_requests_id_seq",
      "assignments_id_seq",
      "auto_merge_requests_id_seq",
      "code_scanning_review_comments_id_seq",
      "commit_comment_edits_id_seq",
      "commit_comment_reactions_id_seq",
      "commit_comments_id_seq",
      "commit_mentions_id_seq",
      "copilot_code_review_comment_feedbacks_id_seq",
      "copilot_code_review_comments_id_seq",
      "copilot_code_review_comment_feedback_choices_id_seq",
      "copilot_code_review_orchestrations_id_seq",
      "cross_references_id_seq",
      "dependabot_autofix_annotations_id_seq",
      "deployment_statuses_id_seq",
      "deployments_id_seq",
      "duplicate_issues_id_seq",
      "issue_alert_links_id_seq",
      "issue_blob_references_id_seq",
      "issue_comment_edits_id_seq",
      "issue_comment_meta_data_blobs_id_seq",
      "issue_comment_orchestrations_id_seq",
      "issue_comment_reactions_id_seq",
      "issue_comments_id_seq",
      "issue_edits_id_seq",
      "issue_dependencies_id_seq",
      "issue_dependency_lists_id_seq",
      "issue_dependency_orchestrations_id_seq",
      "issue_event_authors_id_seq",
      "issue_event_details_id_seq",
      "issue_events_id_seq",
      "issue_imports_id_seq",
      "issue_links_id_seq",
      "issue_orchestrations_id_seq",
      "issue_priorities_id_seq",
      "issue_reactions_id_seq",
      "issue_types_id_seq",
      "issues_id_seq",
      "issues_labels_id_seq",
      "labels_id_seq",
      "last_seen_pull_request_revisions_id_seq",
      "milestones_id_seq",
      "pinned_workflows_id_seq",
      "pull_request_conflicts_id_seq",
      "pull_request_last_pushes_id_seq",
      "pull_request_orchestrations_id_seq",
      "pull_request_review_comment_edits_id_seq",
      "pull_request_review_comment_reactions_id_seq",
      "pull_request_review_comment_orchestrations_id_seq",
      "pull_request_review_comments_id_seq",
      "pull_request_review_edits_id_seq",
      "pull_request_review_points_id_seq",
      "pull_request_review_reactions_id_seq",
      "pull_request_review_threads_id_seq",
      "pull_request_reviews_id_seq",
      "pull_request_reviews_review_requests_id_seq",
      "pull_request_sources_id_seq",
      "pull_request_updates_id_seq",
      "pull_requests_id_seq",
      "repository_issue_types_id_seq",
      "repository_milestones_sequences_id_seq",
      "review_request_reasons_id_seq",
      "review_requests_id_seq",
      "sub_issues_id_seq",
      "sub_issue_lists_id_seq", # issues-pull-requests end
      "pushes_id_seq", # repositories-pushes start
      "ref_pushes_id_seq",
      "ref_updates_id_seq", # repositories-pushes end
      "notification_entries_seq",
      "saved_notification_entries_seq"
    ]

    SPOKES_TABLES = %w[
      cache_storage_policies
      cold_networks
      datacenters
      entity_problems
      fileservers
      gist_replicas
      network_replicas
      repository_checksums
      repository_replicas
      sites
      spokes_key_values
    ]

    STRATOCASTER_TABLES = %w[
      feed_key_values
      stratocaster_events
    ]

    GITBACKUPS_TABLES = %w[
      disabled_backups
      key_versions
      wal
      gist_bases
      gist_incrementals
      gist_maintenance
      repository_bases
      repository_incrementals
      repository_maintenance
      wiki_bases
      wiki_incrementals
      wiki_maintenance
    ]

    COLLAB_TABLES = %w[
      abuse_reports
      achievement_progressions
      achievements
      advisory_credits
      application_callback_urls
      applied_discussion_labels
      audit_log_async_queries
      audit_log_azure_blob_sink_configurations
      audit_log_azure_hubs_sink_configurations
      audit_log_datadog_sink_configurations
      audit_log_git_event_exports
      audit_log_google_cloud_sink_configurations
      audit_log_hec_sink_configurations
      audit_log_s3_sink_configurations
      audit_log_settings
      audit_log_splunk_sink_configurations
      audit_log_stream_configurations
      audit_log_web_exports
      badges
      branch_issue_references
      bulk_dmca_takedowns
      bulk_dmca_takedown_repositories
      bulk_sponsorship_imports
      bulk_sponsorship_tier_selections
      discussions_key_values
      feature_management_key_values
      notices_key_values
      repository_clones
      close_issue_references
      codespace_async_operations
      codespace_billing_entries
      codespace_prebuild_configuration_locations
      codespace_prebuild_configurations
      codespace_prebuild_notification_users
      codespace_prebuild_template_billing_entries
      codespace_prebuild_template_creation_schedules
      codespace_prebuild_templates
      codespace_allowed_permissions
      codespace_unprocessed_billing_messages
      codespace_usage_records
      codespaces_key_values
      codespaces_repository_authorizations
      commit_contribution_summaries
      commit_contributions
      community_insights_daily_counts
      compliance_reports
      compromised_passwords
      compromised_password_datasources
      deceased_users
      deleted_discussions
      deleted_issues
      device_authorization_grants
      discussion_categories
      discussion_category_pins
      discussion_comments
      discussion_comment_edits
      discussion_events
      discussion_reactions
      discussion_comment_reactions
      discussion_sections
      discussion_spotlights
      discussion_transfers
      discussion_polls
      discussion_poll_votes
      discussion_poll_options
      discussions
      discussion_edits
      discussion_votes
      discussion_comment_votes
      enterprise_banner_dismissals
      enterprise_banners
      enterprise_contributions
      enterprise_oidc_issuer_url_customisations
      external_identity_attribute_mappings
      features
      feature_enrollments
      fraud_flagged_sponsors
      git_signing_ssh_public_keys
      global_notices
      gpg_authorizations
      growth_last_activity_key_values
      growth_notice_key_values
      interaction_limits
      ip_allowlist_entries
      issue_transfers
      integration_manifests
      key_links
      marketplace_blog_posts
      mobile_key_values
      organization_discussion_post_replies
      organization_discussion_posts
      organization_discussion_repositories
      organization_oidc_sub_claim_templates
      organization_profiles
      pinned_issues
      pinned_issue_comments
      policy_constraints
      policy_group_memberships
      policy_groups
      repository_advisories
      repository_advisories_key_values
      repository_advisory_affected_products
      repository_advisory_comments
      repository_advisory_events
      repository_contribution_graph_statuses
      repository_network_graphs
      science_events
      enterprise_installation_user_accounts
      enterprise_installation_user_account_emails
      enterprise_installation_user_accounts_uploads
      scoped_integration_installations
      business_user_accounts
      sponsorships
      sponsorship_newsletters
      sponsorship_sift_payment_abuse_scores
      sponsorship_stripe_radar_risk_scores
      ssh_certificate_authorities
      ofac_downgrades
      otp_sms_timings
      integration_aliases
      user_dashboard_pins
      user_reviewed_files
      webauthn_user_handles
      integration_single_files
      sponsorship_newsletter_tiers
      sponsors_listing_stafftools_metadata
      sponsors_listings
      sponsors_patreon_campaign_webhooks
      sponsors_patreon_tiers
      sponsors_patreon_users
      trade_compliance_key_values
      trade_controls_restrictions
      sponsors_tiers
      team_member_delegated_review_requests
      sponsors_criteria
      sponsors_memberships_criteria
      sponsors_business_tax_identifiers
      two_factor_recovery_requests
      user_labels
      pending_automatic_installations
      refresh_tokens
      attribution_invitations
      reminders
      reminder_delivery_times
      reminder_repository_links
      reminder_slack_workspaces
      reminder_team_memberships
      personal_reminders
      reminder_event_subscriptions
      reminder_slack_workspace_memberships
      review_request_delegation_excluded_members
      sponsors_listing_featured_items
      email_domain_reputation_records
      sponsors_activities
      sponsors_activity_metrics
      site_scoped_integration_installations
      user_seen_features
      workspace_plans
      workspaces
      sponsors_fraud_reviews
      acv_contributors
      successor_invitations
      sponsors_goals
      sponsors_goal_contributions
      imports
      repository_imports
      pull_request_imports
      photo_dna_hits
      user_personal_profiles
      sponsorship_match_bans
      potential_sponsorships
      merge_queues
      merge_queue_entries
      merge_queue_entry_stats
      merge_queue_locked_refs
      merge_group_stats
      actions_allowlists
      allowed_action_patterns
      profile_highlights
      profile_highlight_contributions
      sponsors_agreements
      sponsors_agreement_signatures
      sponsors_invoiced_agreement_signatures
      sponsorship_repositories
      stacks_flows
      stacks_instances
      stacks_plans
      stacks_statuses
      stacks_steps
      user_list_items
      user_lists
      user_dashboards
      search_custom_scopes
      search_shortcuts
      stacks_allowlists
      allowed_stacks_patterns
      stacks_analytics
      move_work_items
      move_works
      repository_actions_oidc_configs
      action_packages_metadata
      saved_collections
      saved_views
      ghes_licenses
      weekly_commit_contribution_summaries
      organization_collaborators
      sponsors_key_values
    ]

    COPILOT_TABLES = %w[
      copilot_activities
      copilot_activity_histories
      copilot_administrative_blocks
      copilot_aggregate_usage_details
      copilot_authentication_histories
      copilot_authentications
      copilot_business_trials
      copilot_chat_attachments
      copilot_completion_feedback
      copilot_complimentary_users
      copilot_configurations
      copilot_engaged_oss_repositories
      copilot_engaged_oss_users
      copilot_extensions_agreement_signatures
      copilot_ide_notifications
      copilot_ignores
      copilot_indexed_repositories
      copilot_key_values
      copilot_limited_users
      copilot_organization_events
      copilot_plg_key_values
      copilot_premium_interactions
      copilot_public_users
      copilot_required_authorizations
      copilot_seat_assignments
      copilot_seat_emissions
      copilot_seat_histories
      copilot_seats
      copilot_shared_threads
      copilot_tech_preview_users
      copilot_usage_metrics
      copilot_custom_instructions
      copilot_coding_guidelines
      copilot_coding_guideline_paths
      custom_copilots
      custom_copilot_resources
      integration_agents
      orca_models
      orca_pipeline_groups
      orca_rollouts
      runtime_key_values
      self_serve_banners
    ]

    REPOSITORIES_ACTIONS_CHECKS_TABLES = %w[
      actions_key_values
      artifacts
      artifacts_id_keyspace_idx
      check_annotations
      check_annotations_id_keyspace_idx
      check_runs
      check_runs_id_keyspace_idx
      check_steps
      check_steps_id_keyspace_idx
      check_suites
      check_suites_id_keyspace_idx
      code_scanning_alerts
      code_scanning_alerts_id_keyspace_idx
      code_scanning_check_suites
      code_scanning_check_suites_id_keyspace_idx
      commit_rollups
      commit_rollups_id_keyspace_idx
      dependabot_autofix_annotations
      dependabot_autofix_annotations_id_keyspace_idx
      pinned_workflows
      pinned_workflows_id_keyspace_idx
      statuses
      statuses_id_keyspace_idx
      workflow_job_runs
      workflow_job_runs_id_keyspace_idx
      workflow_run_executions
      workflow_run_executions_id_keyspace_idx
      workflow_runs
      workflow_runs_id_keyspace_idx
      workflows
      workflows_id_keyspace_idx
    ]

    BALLAST_TABLES = %w[
      authenticated_devices
      authentication_records
      collection_items
      collection_urls
      collection_videos
      collections
      content_reference_attachments
      content_references
      discussion_post_replies
      discussion_posts
      explore_key_values
      feed_filter_settings
      feed_post_comments
      feed_post_embeds
      feed_post_references
      feed_posts
      feeds_key_values
      graceful_timeout_key_values
      graphql_client_operations
      graphql_clients
      graphql_index_entries
      graphql_index_references
      graphql_operations
      immutable_actions_opt_outs
      invoiced_sponsorship_transfer_reversals
      invoiced_sponsorship_transfers
      issue_summaries
      job_status_subscription_key_values
      organization_domains
      organization_feed_filter_settings
      pages_embargoed_cnames
      patreon_webhooks
      reserved_logins
      retired_namespaces
      slotted_counters
      stafftools_roles
      stripe_webhooks
      topic_sources
      ui_manifests
      user_stafftools_roles
      web_push_subscriptions
      zuora_webhooks
    ]

    SIGNUP_FLOW_TABLES = %w[
      signup_flow_key_values
    ]

    GITHUB_MODELS_TABLES = %w[
      models_attachments
      models_organization_access_rules
      models_prompts
      models_publishers
    ]

    NOTIFY_TABLES = %w[
      advisory_database_key_values
      code_scanning_key_values
      code_scanning_org_configurations
      cve_epss
      cwe_references
      cwes
      dependabot_key_values
      private_registry_configurations
      reachability_analyses
      reachability_analysis_status_updates
      repository_dependency_updates
      repository_security_center_configs
      repository_security_center_statuses
      repository_security_configurations
      repository_vulnerability_alert_configs
      repository_vulnerability_alert_events
      repository_vulnerability_alert_sequences
      repository_vulnerability_alerts
      repository_vulnerability_exposure_updates
      repository_vulnerable_function_references
      scoped_vulnerabilities
      security_campaign_issues
      security_campaign_team_managers
      security_campaign_user_managers
      security_campaign_users
      security_campaigns
      security_configuration_defaults
      security_configuration_policies
      security_configurations
      security_products_enablement_key_values
      team_group_mappings
      team_sync_business_tenants
      team_sync_tenants
      vulnerabilities
      vulnerability_alert_rule_overrides
      vulnerability_alert_rules
      vulnerability_alerting_event_subscriptions
      vulnerability_alerting_events
      vulnerability_references
      vulnerable_version_range_alerting_processes
      vulnerable_version_ranges
    ]

    TOKEN_SCANNING_SERVICE_PROD_TABLES = %w[
      allowed_secrets
      audit_secret_scanning_pattern_overrides
      audit_token_scan_results
      owner_scopes
      pending_partner_token_notifications
      secret_scanning_bypass_reviewers
      secret_scanning_config_files
      secret_scan_custom_patterns
      secret_scan_incremental_statuses
      secret_scanning_assessment_results
      secret_scanning_assessment_sequences
      secret_scanning_assessments
      secret_scanning_dry_run_results
      secret_scanning_encrypted_secrets
      secret_scanning_encryption_key_hashes
      secret_scanning_incremental_scan_ref_updates
      secret_scanning_job_groups
      secret_scanning_key_values
      secret_scanning_public_leaks
      secret_scanning_pattern_config2owners
      secret_scanning_pattern_config_sequences
      secret_scanning_pattern_configs
      secret_scanning_pattern_override_dbs
      secret_scanning_pattern_overrides
      secret_scanning_push_protection_blocks
      secret_scanning_push_protections_bypass
      secret_scanning_push_protections_bypass_placeholders
      secret_scanning_repos
      secret_scanning_repositories
      secret_scanning_scans
      secret_scanning_token_remediation_events
      secret_scanning_tombstone_jobs
      secret_scanning_validation_multipart_continuations
      secret_scanning_validation_multipart_group_members
      secret_scanning_validation_multipart_groups
      secret_scanning_validation_resets
      secret_scans
      token_scan_statuses
      token_scan_results
      token_scan_result_closure_requests
      token_scan_result_locations_v2
      token_scan_result_sequences
      token_scan_results_validation
      token_scan_location_migration_statuses
      dry_run_scan_results
    ]

    IAM_TABLES = %w[
      abilities_permissions_routing
      fine_grained_permissions
      roles
      user_roles
      role_permissions
    ]

    TABLES_BEING_MIGRATED = []

    MEMEX_TABLES = %w[
      memex_key_values
      memex_projects
      memex_project_charts
      memex_project_columns
      memex_project_column_values
      memex_project_elasticsearch_consistency
      memex_project_items
      memex_project_links
      memex_project_statuses
      memex_project_views
      memex_project_workflows
      memex_project_workflow_actions
      draft_issues
      issue_next_assignments
      project_migrations
      memex_project_visits
      memex_releases
      memex_templates
    ]

    REPOSITORIES_TABLES = %w[
      branch_actor_allowances
      classroom_repositories
      community_profiles
      custom_property_definitions
      custom_property_values
      demo_repositories
      exemption_requests
      exemption_responses
      import_item_errors
      import_items
      integration_allowed_packages
      internal_repositories
      languages
      marketplace_categories_repository_actions
      mirrors
      network_privileges
      org_owned_private_networks_with_forks
      package_download_activities
      package_files
      package_storage_utilizations
      package_version_package_files
      package_versions
      packages_migration
      page_builds
      page_certificates
      page_deployments
      page_updates
      pages
      pages_fileservers
      pages_migrations
      pages_partitions
      pages_protected_domains
      pages_replicas
      pages_routes
      preferred_files
      protected_branches
      reactions
      registry_owner_migration
      registry_package_dependencies
      registry_package_files
      registry_package_metadata
      registry_package_tags
      registry_packages
      release_mentions
      releases
      repositories
      repositories_key_values
      repository_action_releases
      repository_actions
      repository_advisory_comment_edits
      repository_advisory_edits
      repository_auth_versions
      repository_branch_renames
      repository_group_maps
      repository_group_settings
      repository_groups
      repository_invitations
      repository_latest_releases
      repository_licenses
      repository_networks
      repository_orchestrations
      repository_redirects
      repository_rule_conditions
      repository_rule_configurations
      repository_rule_runs
      repository_rule_suite_source_results
      repository_rule_suites
      repository_ruleset_bypass_actors
      repository_ruleset_histories
      repository_rulesets
      repository_sequences
      repository_sponsorables
      repository_stack_releases
      repository_stacks
      repository_tag_protection_states
      repository_topics
      repository_transfers
      repository_unlocks
      repository_wikis
      required_deployments
      required_status_checks
      event_action_ref_updates
      event_action_repository_operations
      review_dismissal_allowances
      tabs
      upload_manifests
    ]

    ISSUES_PULL_REQUESTS_TABLES = %w[
      archived_assignments
      archived_assignments_id_ks_idx
      archived_commit_comments
      archived_commit_comments_id_ks_idx
      archived_deployment_statuses
      archived_deployment_statuses_id_ks_idx
      archived_deployments
      archived_deployments_id_ks_idx
      archived_issue_comments
      archived_issue_comments_id_ks_idx
      archived_issue_event_details
      archived_issue_event_details_id_ks_idx
      archived_issue_events
      archived_issue_events_id_ks_idx
      archived_issues
      archived_issues_id_ks_idx
      archived_labels
      archived_labels_id_ks_idx
      archived_milestones
      archived_milestones_id_ks_idx
      archived_pull_request_review_comments
      archived_pull_request_review_comments_id_ks_idx
      archived_pull_request_review_points
      archived_pull_request_review_points_id_ks_idx
      archived_pull_request_review_threads
      archived_pull_request_review_threads_id_ks_idx
      archived_pull_request_reviews
      archived_pull_request_reviews_id_ks_idx
      archived_pull_request_reviews_review_requests
      archived_pull_request_reviews_review_requests_id_ks_idx
      archived_pull_request_updates
      archived_pull_request_updates_id_ks_idx
      archived_pull_requests
      archived_pull_requests_id_ks_idx
      archived_review_request_reasons
      archived_review_request_reasons_id_ks_idx
      archived_review_requests
      archived_review_requests_id_ks_idx
      assignments
      assignments_id_ks_idx
      auto_merge_requests
      auto_merge_requests_id_ks_idx
      code_scanning_review_comments
      code_scanning_review_comments_id_ks_idx
      commit_comment_edits
      commit_comment_edits_id_ks_idx
      commit_comment_edits_on_user_content_edit_id_ks_idx
      commit_comment_reactions
      commit_comment_reactions_id_ks_idx
      commit_comments
      commit_comments_id_ks_idx
      commit_mentions
      commit_mentions_id_ks_idx
      copilot_code_review_comment_feedback_choices
      copilot_code_review_comment_feedback_choices_id_ks_idx
      copilot_code_review_comment_feedbacks
      copilot_code_review_comment_feedbacks_id_ks_idx
      copilot_code_review_comments
      copilot_code_review_comments_id_ks_idx
      copilot_code_review_orchestrations
      copilot_code_review_orchestrations_id_ks_idx
      cross_references
      cross_references_id_ks_idx
      deployment_statuses
      deployment_statuses_id_ks_idx
      deployments
      deployments_id_ks_idx
      duplicate_issues
      duplicate_issues_id_ks_idx
      ipr_key_values
      issue_alert_links
      issue_alert_links_id_ks_idx
      issue_blob_references
      issue_blob_references_id_ks_idx
      issue_comment_edits
      issue_comment_edits_id_ks_idx
      issue_comment_edits_on_user_content_edit_id_ks_idx
      issue_comment_meta_data_blobs
      issue_comment_meta_data_blobs_id_ks_idx
      issue_comment_orchestrations
      issue_comment_orchestrations_id_ks_idx
      issue_comment_reactions
      issue_comment_reactions_id_ks_idx
      issue_comments
      issue_comments_id_ks_idx
      issue_dependencies
      issue_dependencies_id_ks_idx
      issue_edits
      issue_edits_id_ks_idx
      issue_edits_on_user_content_edit_id_ks_idx
      issue_event_authors
      issue_event_authors_id_ks_idx
      issue_event_details
      issue_event_details_id_ks_idx
      issue_events
      issue_events_id_ks_idx
      issue_imports
      issue_imports_id_ks_idx
      issue_links
      issue_links_id_ks_idx
      issue_orchestrations
      issue_orchestrations_id_ks_idx
      issue_priorities
      issue_priorities_id_ks_idx
      issue_reactions
      issue_reactions_id_ks_idx
      issue_types
      issue_types_id_ks_idx
      issues
      issues_id_ks_idx
      issues_labels
      issues_labels_id_ks_idx
      labels
      labels_id_ks_idx
      last_seen_pull_request_revisions
      last_seen_pull_request_revisions_id_ks_idx
      merge_commit_requests
      milestones
      milestones_id_ks_idx
      pull_request_conflicts
      pull_request_conflicts_id_ks_idx
      pull_request_last_pushes
      pull_request_last_pushes_id_ks_idx
      pull_request_orchestrations
      pull_request_orchestrations_id_ks_idx
      pull_request_review_comment_edits
      pull_request_review_comment_edits_id_ks_idx
      pull_request_review_comment_edits_on_user_content_edit_id_ks_idx
      pull_request_review_comment_orchestrations
      pull_request_review_comment_orchestrations_id_ks_idx
      pull_request_review_comment_reactions
      pull_request_review_comment_reactions_id_ks_idx
      pull_request_review_comments
      pull_request_review_comments_id_ks_idx
      pull_request_review_edits
      pull_request_review_edits_id_ks_idx
      pull_request_review_edits_on_user_content_edit_id_ks_idx
      pull_request_review_points
      pull_request_review_points_id_ks_idx
      pull_request_review_reactions
      pull_request_review_reactions_id_ks_idx
      pull_request_review_threads
      pull_request_review_threads_id_ks_idx
      pull_request_reviews
      pull_request_reviews_id_ks_idx
      pull_request_reviews_review_requests
      pull_request_reviews_review_requests_id_ks_idx
      pull_request_sources
      pull_request_sources_id_ks_idx
      pull_request_updates
      pull_request_updates_id_ks_idx
      pull_requests
      pull_requests_id_ks_idx
      repository_issue_types
      repository_issue_types_id_ks_idx
      repository_milestones_sequences
      repository_milestones_sequences_id_ks_idx
      ref_update_requests
      review_request_reasons
      review_request_reasons_id_ks_idx
      review_requests
      review_requests_id_ks_idx
      sub_issues
      sub_issues_id_ks_idx
      sub_issue_lists
      sub_issue_lists_id_ks_idx
    ]

    REPOSITORIES_PUSHES_SHARDED_TABLES = %w[
      authentic_commits
      pushes
      ref_pushes
      ref_updates
      ref_updates_id_ks_idx
    ]

    BILLING_TABLES = %w[
      actions_cache_usages
      apple_subscriptions
      billing_budgets
      billing_disputes
      billing_external_emails
      billing_key_values
      billing_payouts_ledger_discrepancies
      billing_payouts_ledger_entries
      billing_prepaid_metered_usage_refills
      billing_sales_serve_plan_subscriptions
      billing_transaction_tax_items
      bundled_license_assignments
      contacts
      credit_checks
      enterprise_agreements
      ghas_unbundle_transitions
      google_subscriptions
      licensing_key_values
      licensing_model_transitions
      manual_dunning_periods
      metered_usage_exports
      plan_trials
      sales_serve_subscription_change_request_items
      sales_serve_subscription_change_requests
      shared_storage_artifact_events
      shared_storage_usage
      stripe_connect_accounts
      subscription_sync_statuses
      tax_exemption_statuses
      usage_line_items
      vss_subscription_events
      zuora_rate_plan_charges
    ]

    PAGES_TABLES = %w[
      page_builds
      page_certificates
      page_deployments
      page_updates
      pages
      pages_fileservers
      pages_key_values
      pages_migrations
      pages_partitions
      pages_protected_domains
      pages_replicas
      pages_routes
    ]

    PERMISSIONS_TABLES = %w[
      organization_programmatic_access_grant_requests
      organization_programmatic_access_grants
      permissions
      user_programmatic_access_grant_requests
      user_programmatic_access_grants
      user_programmatic_accesses
    ]

    OCTOSHIFT_TABLES = %w[
      migratable_resources_v2
      migratable_resource_reports
      migration_files
      migration_repositories
      migration_timings
      migrations
      migrations_key_values
      octoshift_migration_archives
    ]

    LODGE_TABLES = %w[
      authentication_tokens
      scoped_integration_installations
      site_scoped_integration_installations
      codespaces_site_scoped_integration_installations
      apps_key_values
    ]

    AUTHND_DOTCOM_MANAGED_TABLES = %w[
      authentication_key_values
    ]

    AUTHND_SERVICE_MANAGED_TABLES = %w[
      mobile_device_keys
      mobile_auth_requests
      programmatic_access_tokens
    ]

    AUTHND_PRODUCTION_TABLES =
      AUTHND_DOTCOM_MANAGED_TABLES +
      AUTHND_SERVICE_MANAGED_TABLES

    SECURITY_OVERVIEW_TABLES = %w[
      soa_dates
      soa_feature_status_revisions
      soa_feature_statuses
      soa_repositories
      soa_dependabot_alert_revisions
      soa_code_scanning_alert_revisions
      soa_code_scanning_pull_request_alerts
      soa_secret_scanning_alert_revisions
      security_center_key_values
    ]

    SECURITY_PRODUCTS_ENABLEMENT_TABLES = %w[
      repository_security_settings
      security_products_enablement_repositories
    ]

    ASSETS_TABLES = %w[
      asset_key_values
    ]

    ACTIONS_ENVIRONMENTS_TABLES = %w[
      environments
      gates
      gate_approvals
      gate_approval_logs
      gate_approvers
      gate_branch_policies
      gate_requests
      pinned_environments
      repository_tech_projects
      repository_tech_project_stacks
    ]

    OUTSIDE_MAIN_CLUSTER_TABLES = CONFIGURATIONS_TABLES +
                                  MYSQL2_TABLES +
                                  NOTIFICATIONS_DELIVERIES_TABLES +
                                  NOTIFICATIONS_ENTRIES_TABLES +
                                  NOTIFICATIONS_SUMMARIES_TABLES +
                                  MYSQL5_TABLES +
                                  SPOKES_TABLES +
                                  GITBACKUPS_TABLES +
                                  COLLAB_TABLES +
                                  COPILOT_TABLES +
                                  BALLAST_TABLES +
                                  GITHUB_MODELS_TABLES +
                                  SIGNUP_FLOW_TABLES +
                                  REPOSITORIES_ACTIONS_CHECKS_TABLES +
                                  NOTIFY_TABLES +
                                  IAM_TABLES +
                                  IAM_ABILITIES_TABLES +
                                  VT_TABLES +
                                  STRATOCASTER_TABLES +
                                  MEMEX_TABLES +
                                  OCTOSHIFT_TABLES +
                                  REPOSITORIES_TABLES +
                                  ISSUES_PULL_REQUESTS_TABLES +
                                  REPOSITORIES_ACTIONS_CHECKS_TABLES +
                                  REPOSITORIES_PUSHES_SHARDED_TABLES +
                                  BILLING_TABLES +
                                  PAGES_TABLES +
                                  PERMISSIONS_TABLES +
                                  TOKEN_SCANNING_SERVICE_PROD_TABLES +
                                  LODGE_TABLES +
                                  SECURITY_OVERVIEW_TABLES +
                                  AUTHND_PRODUCTION_TABLES +
                                  SECURITY_PRODUCTS_ENABLEMENT_TABLES +
                                  ASSETS_TABLES +
                                  ACTIONS_ENVIRONMENTS_TABLES

  end
end
