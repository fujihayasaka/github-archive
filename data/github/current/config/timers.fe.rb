# frozen_string_literal: true

TIMERD_SCRIPT = true

require "timer_daemon"
require "github/config/redis"
require File.expand_path("../basic", __FILE__)
require "github"
require "github/config/stats"
require "github/config/active_job"
require "github/config/active_record"
require "database_selector"
require GitHub::AppEnvironment.root.join("packages/job_scheduling/app/models/job_scheduler")
require "active_support/core_ext/numeric/bytes"
require "active_support/core_ext/numeric/time"
require "github/timeout_and_measure"
require "github/restraint"
require "global_instrumenter"
require "spokes_api"

require "github/config/active_job"
require "github/config/aqueduct"
require "feature_management"
require "github/config/flipper"
require "flipper/vexi_proxy"
require "feature_flag/vexi"
require "github/config/memcache"
require "github/config/hydro"
require "github/faraday_adapter/persistent_excon"
require "active_job/queue_adapters/aqueduct_adapter"
require_relative "instrumentation/jobs"

Hydro.load_schemas(GitHub::AppEnvironment.root.join("lib/hydro"))

require_relative "#{GitHub::AppEnvironment.root}/packages/substrate/app/models/resiliency/response"
require "#{GitHub::AppEnvironment.root}/app/jobs/perform_ofac_downgrades_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/actions/larger_runners_monitor_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/actions/scheduled_delete_action_required_check_suites_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/actions/larger_runners/find_accounts_eligible_for_disable_public_ip_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/audit_log_stream_health_checker_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing_coupon_reminder_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing_delete_obsolete_coupon_expiration_notices_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing_expiring_card_reminders_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing_free_trial_reminder_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing_update_exchange_rates_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/retrieve_failed_zuora_webhooks_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing/azure/check_azure_subscriptions_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing/shared_storage/start_aggregation_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/scheduled_two_factor_recovery_request_notifier_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/two_factor_recovery_request_cleanup_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/two_factor_requirement_discovery_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/two_factor_requirement_progression_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/billing/advanced_security/self_serve_trial_cleanup_search_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing/auth_and_capture/check_billable_entities_metered_usage_for_authorization_thresholds_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/billing/auth_and_capture/check_trials_for_scheduled_authorization_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing/migration/billing_platform_migration_scheduler_job"
require "#{GitHub::AppEnvironment.root}/packages/github_sponsors/app/jobs/billing/check_payouts_ledger_discrepancies_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing/check_unprocessed_sales_serve_webhooks_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing/check_unprocessed_webhooks_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing/check_unsuccessful_subscription_synchronizations_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/perform_pending_plan_changes_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing/synchronize_apple_iap_subscription_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing/synchronize_apple_iap_subscription_items_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing/synchronize_google_iap_subscription_items_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/billing/check_business_organization_transition_failures_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing/check_payment_method_unique_number_identifier_reuse_over_threshold_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/billing/git_lfs_storage_metering_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/business_organization_invitation_review_digest_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/personal_token_expiry_notice_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/packages/remove_func_test_packages_job"
require "#{GitHub::AppEnvironment.root}/packages/apps/app/jobs/proxima_app_sync/synchronize_first_party_apps_job"
require "#{GitHub::AppEnvironment.root}/packages/apps/app/jobs/proxima_app_sync/synchronize_third_party_apps_job"

require "#{GitHub::AppEnvironment.root}/app/jobs/enterprise_onboarding/expire_ghas_trial_job"
require "#{GitHub::AppEnvironment.root}/packages/growth/app/jobs/expire_trial_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/enterprise_onboarding/ghas_trial_eligibility_search_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/purge_soft_deleted_businesses_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/purge_soft_deleted_organizations_job"
require "#{GitHub::AppEnvironment.root}/packages/actions/app/jobs/emit_artifact_expiration_job"
require "#{GitHub::AppEnvironment.root}/packages/admin/app/jobs/business_orchestration_sweeper_job"
require "#{GitHub::AppEnvironment.root}/packages/admin/app/jobs/clean_up_old_business_member_invitations_job"
require "#{GitHub::AppEnvironment.root}/packages/admin/app/jobs/multi_tenant_provisioning_status_update_job"
require "#{GitHub::AppEnvironment.root}/packages/code_scanning/app/jobs/code_scanning_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/billing/cleanup_non_emitting_orgs_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/billing/scheduled_plan_downgrade_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/billing/organizations/scheduled_plan_downgrade_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/business_trials/status_check_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/chat_attachments/maintenance_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/delete_orphaned_seats_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/engaged_oss_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/free_user_coupon_check_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/free_user_check_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/metrics/summary_loader_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/metrics/report_link_job_orchestration_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/paid_user_free_check_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/pending_seat_assignments_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/timed_pending_seat_assignments_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/seat_emission_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/seat_management/duplicate_seat_check_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/seat_management/invalid_seat_cleanup_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot/app/jobs/copilot/seat_management/team_sync_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/abuse/copilot/run_required_authorizations_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing_kv_cleanup_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/billing_run_start_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/scheduled_azure_support_plan_sync_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/scheduled_enterprise_agreement_support_plan_entitle_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/scheduled_enterprise_agreement_support_plan_disentitle_job"
require "#{GitHub::AppEnvironment.root}/packages/licensing/app/jobs/licensing/check_vss_subscription_event_failures_job"
require "#{GitHub::AppEnvironment.root}/packages/licensing/app/jobs/licensing/check_vss_subscription_unprocessed_events_job"
require "#{GitHub::AppEnvironment.root}/packages/licensing/app/jobs/licensing/metered_transition_reminder_job"
require "#{GitHub::AppEnvironment.root}/packages/licensing/app/jobs/licensing/trigger_scheduled_licensing_model_transitions_job"
require "#{GitHub::AppEnvironment.root}/packages/licensing/app/jobs/licensing/trigger_scheduled_ghas_unbundle_transitions_job"
require "#{GitHub::AppEnvironment.root}/packages/orgs/app/jobs/organization_orchestration_sweeper_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces_cache_skus_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces_cleanup_unprocessed_billing_messages_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces_fetch_billing_storage_account_names_dev_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces_fetch_billing_storage_account_names_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces_fetch_billing_storage_account_names_ppe_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces_check_for_hung_async_operations_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces_kv_cleanup_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces/upcoming_retention_notification_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces/past_retention_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces/purge_soft_deleted_codespaces_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces/check_failover_status_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces/check_for_shutdown_codespaces_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces/enqueue_upcoming_template_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces/watch_orphaned_prebuild_templates_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces/clean_up_stuck_provisioning_job"
require "#{GitHub::AppEnvironment.root}/packages/codespaces/app/jobs/codespaces/suspend_stale_spark_workbench_codespaces_job"
require "#{GitHub::AppEnvironment.root}/packages/orgs/app/jobs/team_orchestration_sweeper_job"
require "#{GitHub::AppEnvironment.root}/packages/gists/app/jobs/gist_maintenance_scheduler_job"
require "#{GitHub::AppEnvironment.root}/packages/gists/app/jobs/gist_purge_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/trust_tier_update_engaged_oss_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/emu_contribution_sharing_sync_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/migrate_business_provider_job"
require "#{GitHub::AppEnvironment.root}/packages/branch_protections/app/jobs/ruleset_sweeper_job"
require "#{GitHub::AppEnvironment.root}/packages/checks/app/jobs/checks_job_utility"
require "#{GitHub::AppEnvironment.root}/packages/checks/app/jobs/check_steps_orchestrate_deletion_job"
require "#{GitHub::AppEnvironment.root}/packages/checks/app/jobs/check_suites_archive_orchestration_job"
require "#{GitHub::AppEnvironment.root}/packages/checks/app/jobs/check_suites_delete_archived_orchestration_job"
require "#{GitHub::AppEnvironment.root}/packages/statuses/app/jobs/statuses_archive_orchestration_job"
require "#{GitHub::AppEnvironment.root}/packages/statuses/app/jobs/statuses_delete_archived_orchestration_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/packages/migration/notify_inprogress_migration_job"
require "#{GitHub::AppEnvironment.root}/packages/planning/app/jobs/purge_expired_memex_elasticsearch_consistency_scores_job"
require "#{GitHub::AppEnvironment.root}/packages/planning/app/jobs/report_memex_project_items_index_consistency_metric_job"
require "#{GitHub::AppEnvironment.root}/packages/planning/app/jobs/queue_memex_elasticsearch_resyncs_job"
require "#{GitHub::AppEnvironment.root}/packages/planning/app/jobs/memex_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/packages/pull_requests/app/jobs/ipr_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/packages/repositories/app/jobs/calculate_topic_applied_counts_job"
require "#{GitHub::AppEnvironment.root}/packages/repositories/app/jobs/remove_expired_announcements_job"
require "#{GitHub::AppEnvironment.root}/packages/repositories/app/jobs/repository_bulk_purge_job"
require "#{GitHub::AppEnvironment.root}/packages/repositories/app/jobs/check_org_owned_private_networks_with_forks_job"
require "#{GitHub::AppEnvironment.root}/packages/repositories/app/jobs/scheduled_archive_dangling_forks_job"
require "#{GitHub::AppEnvironment.root}/packages/repositories/app/jobs/mirror_scheduler_job"
require "#{GitHub::AppEnvironment.root}/packages/repositories/app/jobs/repository_orchestration_sweeper_job"
require "#{GitHub::AppEnvironment.root}/packages/issues/app/jobs/issue_orchestration_sweeper_job"
require "#{GitHub::AppEnvironment.root}/packages/pull_requests/app/jobs/pull_request_orchestration_sweeper_job"
require "#{GitHub::AppEnvironment.root}/packages/security_products/app/jobs/codeql_bulk_builder_job"
require "#{GitHub::AppEnvironment.root}/packages/security_products/app/jobs/codeql_database_cleanup_scheduler_job"
require "#{GitHub::AppEnvironment.root}/packages/security_products/app/jobs/codeql_variant_analysis_finalizer_job"
require "#{GitHub::AppEnvironment.root}/packages/security_products/app/jobs/security_campaigns/overdue_scheduler_job"
require "#{GitHub::AppEnvironment.root}/packages/security_products/app/jobs/security_center/dead_letter_job"
require "#{GitHub::AppEnvironment.root}/packages/security_products/app/jobs/security_center/kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/memex_hydro_project_automation/instrumentation/shared"
require "#{GitHub::AppEnvironment.root}/app/jobs/memex_hydro_project_automation/instrumentation/scheduled_runner"
require "#{GitHub::AppEnvironment.root}/app/jobs/memex_project_workflow_scheduled_runner_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/aqueduct_test_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/actions/scheduled_sync_dependents_count_repo_action_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/actions/scheduled_sync_dependents_count_repo_action_using_batch_dg_api_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/stop_all_stalled_progress_job"
require "#{GitHub::AppEnvironment.root}/packages/issues/app/jobs/dangling_issue_orchestration_starter_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/clean_locks_job"
require "#{GitHub::AppEnvironment.root}/packages/users/app/jobs/purge_orphaned_followers_job"
require "#{GitHub::AppEnvironment.root}/lib/background_job_queues"
require "#{GitHub::AppEnvironment.root}/packages/community_and_safety/app/jobs/clean_expired_interaction_limits_job"
require "#{GitHub::AppEnvironment.root}/packages/github_models/app/jobs/github_models_job"
require "#{GitHub::AppEnvironment.root}/packages/github_models/app/jobs/github_models/fetch_catalog_items_job"
require "#{GitHub::AppEnvironment.root}/packages/github_models/app/jobs/github_models/calculate_model_popularity_job"
require "#{GitHub::AppEnvironment.root}/packages/discussions/app/jobs/discussions_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/packages/discussions/app/jobs/publish_scheduled_discussions_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/feeds_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/packages/security_products_enablement/app/jobs/security_products_enablement_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/connect_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/enterprise_accounts_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/orgs_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/organization_invitation_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/site_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/repository_advisories_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/apps_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/advisory_database_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/sponsors_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/teams_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/trust_safety_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/dependabot_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/mobile_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/external_identities_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/packages/copilot4prs/app/jobs/pending_code_review_requests_sweeper_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/clean_up_old_organization_invitations_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/pages_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/packages/repositories/app/jobs/repositories_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/assets_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/marketplace_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/spokes_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/licensing_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/search_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/copilot_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/packages/spark_runtime/app/jobs/spark_runtime_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/monitor_enterprise_access_verification_usage_job"

## Dependency Graph jobs
require "#{GitHub::AppEnvironment.root}/packages/dependency_graph/app/jobs/dependency_graph/retry_job"
require "#{GitHub::AppEnvironment.root}/packages/dependency_graph/app/jobs/dependency_graph/scheduled_disable_inactive_repos_job"

## Notifications jobs
require "#{GitHub::AppEnvironment.root}/packages/notifications/app/jobs/newsies_auto_subscribe_job"
require "#{GitHub::AppEnvironment.root}/packages/notifications/app/jobs/delete_expired_notifications_key_values_job"
require "#{GitHub::AppEnvironment.root}/packages/notifications/app/jobs/delete_expired_notification_summaries_tier1_job"
require "#{GitHub::AppEnvironment.root}/packages/notifications/app/jobs/delete_expired_notification_summaries_tier2_job"
require "#{GitHub::AppEnvironment.root}/packages/notifications/app/jobs/delete_expired_notification_summaries_tier3_job"
require "#{GitHub::AppEnvironment.root}/packages/notifications/app/jobs/delete_expired_notification_summaries_tier4_job"
require "#{GitHub::AppEnvironment.root}/packages/notifications/app/jobs/delete_expired_notification_summaries_tier5_job"

# Credit Decision Engine
require "#{GitHub::AppEnvironment.root}/packages/credit_decision_engine/app/public/credit_decision_engine"
require "#{GitHub::AppEnvironment.root}/packages/credit_decision_engine/app/jobs/credit_decision_engine/abstract_credit_check_status_poll_job"
require "#{GitHub::AppEnvironment.root}/packages/billing/app/jobs/credit_check_status_poll_job"

# Trade Compliance
require "#{GitHub::AppEnvironment.root}/packages/trade_compliance/app/public/trade_compliance"
require "#{GitHub::AppEnvironment.root}/packages/trade_compliance/app/public/trade_compliance/trade_screening"
require "#{GitHub::AppEnvironment.root}/packages/trade_compliance/app/jobs/trade_compliance/trade_screening/kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/packages/trade_compliance/app/jobs/trade_compliance/trade_screening/eis_poll_job"
require "#{GitHub::AppEnvironment.root}/packages/trade_compliance/app/jobs/trade_compliance/trade_screening/perform_screening_retry_job"

# Feature Management
require "#{GitHub::AppEnvironment.root}/packages/management_tools/app/jobs/feature_management_kv_cleanup_expired_data_job"
require "#{GitHub::AppEnvironment.root}/app/jobs/feature_management/curated_segments_update_job"

# Growth
require "#{GitHub::AppEnvironment.root}/packages/growth/app/jobs/nurture/cpm_sync_job"

require_relative "../packages/users/app/jobs/users_kv_cleanup_expired_data_job"
require_relative "../packages/profiles/app/jobs/profiles_kv_cleanup_expired_data_job"
require_relative "../packages/stars/app/jobs/stars_kv_cleanup_expired_data_job"
require_relative "../packages/explore/app/jobs/explore_kv_cleanup_expired_data_job"
require_relative "../packages/management_tools/app/jobs/notices_kv_cleanup_expired_data_job"

# This load private implementation of the job and the public helper exposing the class name of the job
require "#{GitHub::AppEnvironment.root}/packages/security_overview_analytics/app/public/security_overview_analytics/scheduler_job"

require "#{GitHub::AppEnvironment.root}/packages/apps/app/jobs/cleanup_expired_permissions_job"

require "#{GitHub::AppEnvironment.root}/packages/security_products_enablement/app/jobs/security_products_enablement/progress_tracker_keys_monitor_job"
require "#{GitHub::AppEnvironment.root}/packages/security_products_enablement/app/jobs/security_products_enablement/clean_up_stuck_in_attaching_job"

require "#{GitHub::AppEnvironment.root}/packages/global_notices/app/jobs/scheduled_global_notice_refresh_job"

# configure ActiveJob
ActiveJob::Base.queue_adapter = :aqueduct

# configure daemon
daemon = TimerDaemon.instance
daemon.err = GitHub.logger.method(:info)
daemon.redis = GitHub.legacy_redis
scheduler = JobScheduler.new(daemon)

ScheduledFeTimerError = Class.new(StandardError)

# report exceptions to Failbot
daemon.error do |boom, timer|
  begin
    begin
      raise boom
    rescue boom.class
      raise ScheduledFeTimerError.new("timer #{timer.name} failed")
    end
  rescue ScheduledFeTimerError => wrapped
    Failbot.report(wrapped, timer: timer.name)
  end
end

daemon.schedule "timerd-heartbeat-fe-global", 10.seconds do
  GitHub.dogstats.increment "timerd.heartbeat", tags: ["config:fe", "scope:global"]
end

daemon.schedule "timerd-heartbeat-fe-host", 10.seconds, scope: :host do
  GitHub.dogstats.increment "timerd.heartbeat", tags: ["config:fe", "scope:host"]
end

daemon.schedule "dgit-disk-stats-timer", GitHub.dgit_disk_stats_interval do
  DatabaseSelector.instance.track_writes(DatabaseSelector::LastOperations.empty) do
    SpokesDiskStatsCacheFillJob.perform_later(Time.now.to_i)
  end
end

daemon.schedule "dotcom-worker-monitor", AqueductTestJob::MONITOR_JOB_INTERVAL, scope: :host do
  DatabaseSelector.instance.track_writes(DatabaseSelector::LastOperations.empty) do
    BackgroundJobQueues.monitor_queue_names.each do |queue_name|
      AqueductTestJob.set(queue: queue_name).perform_later
    end
  end
end

[
  # Billing
  PerformManualDunningPeriodJob,
  PerformPendingPlanChangesJob,
  BillingCouponReminderJob,
  BillingDeleteObsoleteCouponExpirationNoticesJob,
  BillingExpiringCardRemindersJob,
  BillingUpdateExchangeRatesJob,
  BillingRunStartJob,
  EnsureRecentlyUpdatedPayoutsLedgersInBalanceJob,
  BillingFreeTrialReminderJob,
  PerformOFACDowngradesJob,
  RetrieveFailedZuoraWebhooksJob,
  YearlyCycleNoticeStartJob,
  Billing::SharedStorage::StartAggregationJob,
  Billing::Azure::CheckAzureSubscriptionsJob,
  Billing::CheckPayoutsLedgerDiscrepanciesJob,
  Billing::CheckUnprocessedWebhooksJob,
  Billing::CheckUnprocessedSalesServeWebhooksJob,
  Billing::CheckUnsuccessfulSubscriptionSynchronizationsJob,
  Billing::SynchronizeAppleIapSubscriptionJob,
  Billing::SynchronizeAppleIapSubscriptionItemsJob,
  Billing::SynchronizeGoogleIapSubscriptionItemsJob,
  Billing::CheckBusinessOrganizationTransitionFailuresJob,
  Billing::CheckPaymentMethodUniqueNumberIdentifierReuseOverThresholdJob,
  Billing::GitLfsStorageMeteringJob,
  Billing::AuthAndCapture::CheckBillableEntitiesMeteredUsageForAuthorizationThresholdsJob,
  Billing::AuthAndCapture::CheckTrialsForScheduledAuthorizationJob,
  Billing::Migration::BillingPlatformMigrationSchedulerJob,
  BillingKvCleanupJob,
  CreditCheckStatusPollJob,
  ScheduledAzureSupportPlanSyncJob,
  ScheduledEnterpriseAgreementSupportPlanEntitleJob,
  ScheduledEnterpriseAgreementSupportPlanDisentitleJob,
  Abuse::Copilot::RunRequiredAuthorizationsJob,

  # Licensing
  Licensing::CheckVssSubscriptionEventFailuresJob,
  Licensing::CheckVssSubscriptionUnprocessedEventsJob,
  Licensing::MeteredTransitionReminderJob,
  Licensing::TriggerScheduledLicensingModelTransitionsJob,
  Licensing::TriggerScheduledGhasUnbundleTransitionsJob,

  # Cached Topics stats
  CalculateTopicAppliedCountsJob,

  NewsletterDeliveryJob,

  # Git Maintenance
  NetworkMaintenanceSchedulerJob,
  WikiMaintenanceSchedulerJob,
  GistMaintenanceSchedulerJob,

  QueueMediaTransitionJobsJob,

  ###
  # Notifications
  ###
  NewsiesAutoSubscribeJob,  # Iterates through all users in `notification_subscriptions`
  # clean up expired entries on mysql2/notification_key_values
  DeleteExpiredNotificationsKeyValuesJob,
  DeleteExpiredNotificationSummariesTier1Job,
  DeleteExpiredNotificationSummariesTier2Job,
  DeleteExpiredNotificationSummariesTier3Job,
  DeleteExpiredNotificationSummariesTier4Job,
  DeleteExpiredNotificationSummariesTier5Job,


  RemoveExpiredOauthJob,
  RemoveStaleOauthJob,
  RemoveStalePublicKeysJob,
  RemoveStaleAuthenticationRecordsJob,
  RemoveStaleAuthenticatedDevicesJob,

  OtpSmsTimingCleanupJob,

  # grab nexmo sms provider account balance
  NexmoBalanceStatsJob,

  SyncAssetUsageSchedulerJob,

  # orchestrations
  DanglingIssueOrchestrationStarterJob,
  RepositoryOrchestrationSweeperJob,
  IssueOrchestrationSweeperJob,
  PullRequestOrchestrationSweeperJob,

  # Network maintenance
  CheckOrgOwnedPrivateNetworksWithForksJob,

  # deleting stuff
  RulesetSweeperJob,
  MigrationEnqueueDestroyFileJobsJob,
  PurgeArchivedAssetsJob,
  PurgeRestorablesJob,
  RepositoryBulkPurgeJob,
  GistPurgeJob,
  DestroyDeletedPackageVersionsJob,
  PurgeFlaggedUploadsJob,
  Packages::RemoveFuncTestPackagesJob,
  DeleteExpiredReservedLoginTombstonesJob,
  ActionsKvCleanupExpiredDataJob,
  PurgeOrphanedFollowersJob,
  GrowthNoticeKvCleanupExpiredDataJob,
  GrowthLastActivityKvCleanupExpiredDataJob,
  PurgeSoftDeletedOrganizationsJob,
  IprKvCleanupExpiredDataJob,
  FeedsKvCleanupExpiredDataJob,
  SecurityProductsEnablementKvCleanupExpiredDataJob,
  ConnectKvCleanupExpiredDataJob,
  EnterpriseAccountsKvCleanupExpiredDataJob,
  OrgsKvCleanupExpiredDataJob,
  OrganizationInvitationKvCleanupExpiredDataJob,
  SiteKvCleanupExpiredDataJob,
  RepositoryAdvisoriesKvCleanupExpiredDataJob,
  EnqueueOctoshiftMigrationArchiveDestroyJobsJob,
  AppsKvCleanupExpiredDataJob,
  AdvisoryDatabaseKvCleanupExpiredDataJob,
  SponsorsKvCleanupExpiredDataJob,
  TeamsKvCleanupExpiredDataJob,
  TrustSafetyKvCleanupExpiredDataJob,
  ExternalIdentitiesKvCleanupExpiredDataJob,
  DependabotKvCleanupExpiredDataJob,
  MobileKvCleanupExpiredDataJob,
  CleanUpOldOrganizationInvitationsJob,
  PagesKvCleanupExpiredDataJob,
  AssetsKvCleanupExpiredDataJob,
  MarketplaceKvCleanupExpiredDataJob,
  SpokesKvCleanupExpiredDataJob,
  LicensingKvCleanupExpiredDataJob,
  SearchKvCleanupExpiredDataJob,
  CopilotKvCleanupExpiredDataJob,
  CleanUpOldBusinessMemberInvitationsJob,

  # Migration storage monitoring
  OctoshiftStorageMonitoringJob,

  # archive
  ScheduledArchiveDanglingForksJob,

  # spam
  UpdateUserHiddenMismatchesJob,
  SpamKvCleanupJob,

  # Authentication
  QintelImportNewFiles,
  ScheduledTwoFactorRecoveryRequestNotifierJob,
  TwoFactorRecoveryRequestCleanupJob,
  AuthenticationKvCleanupExpiredDataJob,
  AuthenticatedAfterTwoFactorRecoveryRequestJob,
  TwoFactorRequiredNotifierJob,
  TwoFactorRequirementDiscoveryJob,
  TwoFactorRequirementProgressionJob,
  ScheduledGlobalNoticeRefreshJob,

  # Git Backups
  GitbackupsSchedulerJob,
  GitbackupsSweeperJob,
  GitbackupsEnsureFreshKeyJob,
  GitbackupsMigrationSchedulerJob,

  # GitHub Models
  GitHubModels::CalculateModelPopularityJob,
  GitHubModels::FetchCatalogItemsJob,

  # Marketplace
  UpdateMarketplaceInsightsJob,
  MarketplaceBlogSyncJob,
  SyncMarketplaceSearchIndexJob,

  MirrorSchedulerJob,

  # Supply Chain
  DependabotSecurityUpdateTimeoutCleanupJob,
  VulnerabilityAlertingEventProcessObserverJob,

  # code scanning
  StaleCodeScanningCheckRunsScheduledJob,
  CodeqlBulkBuilderJob,
  CodeqlDatabaseCleanupSchedulerJob,
  CodeqlVariantAnalysisFinalizerJob,
  SecurityCampaigns::OverdueSchedulerJob,
  CodeScanningKvCleanupExpiredDataJob,

  ExampleScheduledJob,

  EnqueueAqueductTestJob,
  AqueductRelayTestJob,

  ScienceEventCleanupJob,

  # feature-management
  StaleCheckJob,

  EnqueueUpcomingRemindersJob,

  # Enterprise accounts
  BusinessOrganizationInvitationReviewDigestJob,
  BusinessTrialExpirationJob,
  BusinessTrialRestoreUpgradeStateJob,
  BusinessReportExportsCleanupJob,
  InvalidateExpiredInvitesJob,
  ExpireBusinessAdminInvitationsJob,
  ExpireBusinessOrganizationInvitationsJob,
  SendBusinessOrganizationInvitationRemindersJob,
  PurgeSoftDeletedBusinessesJob,
  PurgeCancelledTrialsJob,
  NotifyExpiredTrialsJob,
  DeleteExpiredTrialsJob,
  MultiTenantProvisioningStatusUpdateJob,
  BusinessOrchestrationSweeperJob,

  # Delete redundant business organization invitations
  DeleteRedundantBusinessOrganizationInvitationsJob,

  # Organizations
  OrganizationOrchestrationSweeperJob,

  # Copilot
  Copilot::Billing::CleanupNonEmittingOrgsJob,
  Copilot::Billing::ScheduledPlanDowngradeJob,
  Copilot::Billing::Organizations::ScheduledPlanDowngradeJob,
  Copilot::BusinessTrials::StatusCheckJob,
  Copilot::ChatAttachments::MaintenanceJob,
  Copilot::DeleteOrphanedSeatsJob,
  Copilot::EngagedOssJob,
  Copilot::FreeUserCouponCheckJob,
  Copilot::FreeUserCheckJob,
  Copilot::Metrics::ReportLinkJobOrchestrationJob,
  Copilot::PaidUserFreeCheckJob,
  Copilot::PendingSeatAssignmentsJob,
  Copilot::TimedPendingSeatAssignmentsJob,
  Copilot::SeatEmissionJob,
  Copilot::SeatManagement::DuplicateSeatCheckJob,
  Copilot::SeatManagement::InvalidSeatCleanupJob,
  Copilot::SeatManagement::TeamSyncJob,

  # Codespaces
  CodespacesCacheSkusJob,
  CodespacesCheckForHungAsyncOperationsJob,
  CodespacesCleanupUnprocessedBillingMessagesJob,
  CodespacesFetchBillingStorageAccountNamesDevJob,
  CodespacesFetchBillingStorageAccountNamesJob,
  CodespacesFetchBillingStorageAccountNamesPpeJob,
  Codespaces::CheckFailoverStatusJob,
  Codespaces::CheckForShutdownCodespacesJob,
  Codespaces::EnqueueUpcomingTemplateJob,
  Codespaces::PastRetentionJob,
  Codespaces::PurgeSoftDeletedCodespacesJob,
  Codespaces::UpcomingRetentionNotificationJob,
  Codespaces::WatchOrphanedPrebuildTemplatesJob,
  Codespaces::CleanUpStuckProvisioningJob,
  CodespacesKvCleanupJob,
  Codespaces::SuspendStaleSparkWorkbenchCodespacesJob,

  # Trade Compliance
  TradeCompliance::TradeScreening::KvCleanupExpiredDataJob,
  TradeCompliance::TradeScreening::EisPollJob,
  TradeCompliance::TradeScreening::PerformScreeningRetryJob,

  # Advanced Security
  MeteredAdvancedSecurityScheduledEmitterJob,

  # projects
  BatchedEnqueueMemexProjectColumnIterationUpdateJob,
  PurgeDeletedMemexProjectsJob,
  MemexKvCleanupExpiredDataJob,
  MemexWaitlistProcessorJob,
  ReportMemexProjectItemsIndexConsistencyMetricJob,
  QueueMemexElasticsearchResyncsJob,

  # Actions & Checks
  Actions::ScheduledDeleteActionRequiredCheckSuitesJob,
  Actions::LargerRunnersMonitorJob,

  # Actions & Larger Runners
  Actions::LargerRunners::FindAccountsEligibleForDisablePublicIpJob,

  CheckStepsOrchestrateDeletionJob,
  CheckSuitesArchiveOrchestrationJob,
  CheckSuitesDeleteArchivedOrchestrationJob,
  StatusesArchiveOrchestrationJob,
  StatusesDeleteArchivedOrchestrationJob,
  EmitArtifactExpirationJob,

  # PAT Expiry Notices
  PersonalTokenExpiryNoticeJob,
  PersonalTokenExpiredNoticeJob,

  # PAT Request Notices
  NotifyOrgAdminsAboutPatRequestsJob,

  # Proxima App Sync
  ProximaAppSync::SynchronizeFirstPartyAppsJob,
  ProximaAppSync::SynchronizeThirdPartyAppsJob,

  # EMUs
  EmuContributionSharingSyncJob,
  MigrateBusinessProviderJob,
  ScanEmuExternalTeamsJob,
  ScanEmuOrganizationMembershipsJob,
  ScanEmuOrganizationUsersJob,
  MonitorEnterpriseAccessVerificationUsageJob,

  # GHAS Trial removal
  EnterpriseOnboarding::ExpireGhasTrialJob,

  # GHAS Trial eligibility
  EnterpriseOnboarding::GhasTrialEligibilitySearchJob,
  # Advanced Security self-serve trial expiry cleanup
  Billing::AdvancedSecurity::SelfServeTrialCleanupSearchJob,

  # Secret Protection & Code Security trials
  ExpireTrialJob,

  # Org admin notification about requested features
  MemberFeatureRequestNotificationJob,

  # GitHub for Startups Renewal email
  StartupProgramRenewalEmailJob,

  # GitHub for Startups Coupon EA email
  StartupProgramCouponEmailJob,

  # Expiring announcements
  RemoveExpiredAnnouncementsJob,

  # Trust tiers
  TrustTierUpdateEngagedOssJob,

  # Teams
  CleanUpDeletedTeamsJob,
  TeamOrchestrationSweeperJob,

  # Packages
  Packages::Migration::NotifyInprogressMigrationJob,

  # Memex Automation
  MemexProjectWorkflowScheduledRunnerJob,

  # Sync dependents count for actions
  Actions::ScheduledSyncDependentsCountRepoActionJob,

  # Distributed progress tracking
  StopAllStalledProgressJob,

  # Sync dependents count for actions using batched dg api
  Actions::ScheduledSyncDependentsCountRepoActionUsingBatchDgApiJob,

  # Security Center Analytics
  SecurityOverviewAnalytics::SchedulerJob,

  # Security Center
  SecurityCenter::DeadLetterJob,
  SecurityCenter::KvCleanupExpiredDataJob,

  # Job system cleanup
  CleanLocksJob,

  # Audit log
  AuditLogStreamHealthCheckerJob,

  # Community & Safety
  CleanExpiredInteractionLimitsJob,

  # Signup Flow
  SignupFlowKvCleanupExpiredDataJob,

  # Growth
  Nurture::CpmSyncJob,

  # GitHub Apps
  CleanupExpiredPermissionsJob,

  # Discussions
  DiscussionsKvCleanupExpiredDataJob,
  PublishScheduledDiscussionsJob,

  # Feature Management
  FeatureManagementKvCleanupExpiredDataJob,
  FeatureManagement::CuratedSegmentsUpdateJob,

  # Security products enablement
  SecurityProductsEnablement::ProgressTrackerKeysMonitorJob,
  SecurityProductsEnablement::CleanUpStuckInAttachingJob,

  # Dependency Graph
  DependencyGraph::ScheduledDisableInactiveReposJob,

  UsersKvCleanupExpiredDataJob,
  ProfilesKvCleanupExpiredDataJob,
  StarsKvCleanupExpiredDataJob,
  ExploreKvCleanupExpiredDataJob,
  PendingCodeReviewRequestsSweeperJob,
  NoticesKvCleanupExpiredDataJob,
  RepositoriesKvCleanupExpiredDataJob,
  SparkRuntimeKvCleanupExpiredDataJob,
].each do |job|
  scheduler.schedule job
end

# Search engine indexing
scheduler.schedule "SearchEngineIndexing::EnqueueUsersForIndexingJob", interval: 1.day, condition: -> { !GitHub.enterprise? }
scheduler.schedule "SearchEngineIndexing::EnqueueRepositoriesForIndexingJob", interval: 1.hour, condition: -> { !GitHub.enterprise? }

scheduler.schedule "FeatureShowcasesJob", interval: 1.day
scheduler.schedule "MailchimpDataQualitySyncJob", interval: 1.week

# Sponsors
scheduler.schedule "AutoAcceptSponsorsApplicationsJob", interval: 2.hours, condition: -> { GitHub.sponsors_enabled? }
scheduler.schedule "CancelSponsorshipsFromAbusiveSponsorsJob", interval: 1.day, condition: -> { GitHub.sponsors_enabled? }
scheduler.schedule "DeactivateExpiredSponsorshipsJob", interval: 1.day, condition: -> { GitHub.sponsors_enabled? }
scheduler.schedule "EnableSponsorsPayoutsJob", interval: 1.day, condition: -> { GitHub.sponsors_enabled? }
scheduler.schedule "PopulateSponsorsFraudReviewsJob", interval: 4.hours, condition: -> { GitHub.sponsors_enabled? }
scheduler.schedule "ReviewPendingSponsorsListingsJob", interval: 2.hours, condition: -> { GitHub.sponsors_enabled? }
scheduler.schedule "SponsorsProfileSetupReminderJob", interval: 1.day, condition: -> { GitHub.sponsors_enabled? }
scheduler.schedule "SyncSponsorsStripeAccountsJob", interval: 5.minutes, condition: -> { GitHub.sponsors_enabled? }
scheduler.schedule "UpdateSponsorsActivityMetricsJob", interval: 1.day, condition: -> { GitHub.sponsors_enabled? }
scheduler.schedule "ScheduledSponsorsPatreonSyncJob", interval: 24.hours, condition: -> { GitHub.sponsors_enabled? }

# Pages
scheduler.schedule "DeleteDependentPagesReplicasSchedulerJob", interval: 1.day, scope: :global
scheduler.schedule "DpagesEvacuationSchedulerJob", interval: 3.minutes
scheduler.schedule "DpagesMaintenanceSchedulerJob", interval: GitHub.dpages_maintenance_scheduler_schedule_interval
scheduler.schedule "PageCertificateRemoveDuplicateJob", interval: 1.hour, condition: -> { GitHub.fastly_enabled? && GitHub.pages_custom_domain_https_enabled? }
scheduler.schedule "PageCertificateRemoveExpiredJob", interval: 1.hour, condition: -> { GitHub.fastly_enabled? && GitHub.pages_custom_domain_https_enabled? }
scheduler.schedule "PageCertificateRenewJob", interval: 30.seconds, condition: -> { GitHub.pages_custom_domain_https_enabled? }
scheduler.schedule "PageMigrateHostSchedulerJob", interval: 2.minutes
scheduler.schedule "Pages::DestroySoftDeletedPagesJob", interval: 12.hours
scheduler.schedule "Pages::ProcessPendingDomainsJob", interval: 12.hours
scheduler.schedule "Pages::VerifyDomainsJob", interval: 7.days

# Growth
scheduler.schedule "MemberFeatureRequest::SyncCopilotForBusinessSeatStatusJob", interval: 24.hours

# Copilot
scheduler.schedule "PullRequests::Copilot::ScheduledSummariesFeedbackCleanupJob", interval: 1.day, condition: -> { !GitHub.enterprise? }
scheduler.schedule "Copilot::SeatManagement::SuspendedUserSeatsJob", interval: 2.hours, condition: -> { GitHub.copilot_for_business_enabled? }
scheduler.schedule "Copilot::FreeUserUpgradeJob", interval: 1.day, condition: -> { GitHub.copilot_enabled? }

# GitHub Apps
scheduler.schedule "CleanupOrphanedBotsJob", interval: 7.days

# Advisory Database
scheduler.schedule "EPSSIngestionJob", interval: 1.day, condition: -> { !GitHub.enterprise? }

# Billing
scheduler.schedule "Billing::UpcomingGheRenewalCheckJob", interval: 1.day, condition: -> { !GitHub.enterprise? }
scheduler.schedule "Billing::OnboardBillingPlatformCohortByDateKickoffJob", interval: 1.day, condition: -> { !GitHub.enterprise? }
scheduler.schedule "Billing::OnboardCohortIn7DaysAdminAlertJob", interval: 1.day, condition: -> { !GitHub.enterprise? }
scheduler.schedule "Billing::OnboardBillingPlatformBackgroundJob", interval: 1.minute, condition: -> { !GitHub.enterprise? }
scheduler.schedule "Billing::DailyCustomerWithoutPaymentInformationDunningCheckJob", interval: 1.hour, condition: -> { !GitHub.enterprise? }

# Advanced Security
# Note: these queues are throttled in aqueduct today. Disable or update throttling as needed if schedule intervals are modified.
# See https://thehub.github.com/epd/engineering/products-and-services/dotcom/background-jobs/chatops/#throttling-queues
scheduler.schedule "AdvancedSecurity::LockMeteredUsageScheduledJob", interval: 1.day, condition: -> { !GitHub.enterprise? }
scheduler.schedule "AdvancedSecurity::UnlockMeteredUsageScheduledJob", interval: 10.minutes, condition: -> { !GitHub.enterprise? }

# Projects
scheduler.schedule "PurgeExpiredMemexElasticsearchConsistencyScoresJob", interval: 1.day
