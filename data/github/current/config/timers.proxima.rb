# frozen_string_literal: true

TIMERD_SCRIPT = true

require "timer_daemon"
require "github/config/redis"
require File.expand_path("../basic", __FILE__)
require "github"
require "github/config/stats"
require "github/config/active_job"
require GitHub::AppEnvironment.root.join("packages/job_scheduling/app/models/job_scheduler")
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/numeric/bytes"
require "github/timeout_and_measure"
require "github/config/active_record"
require "github/pages/allocator"
require "github/sql"
require "github/dgit"
require "global_instrumenter"
require "raindrops"
require "spokes_api"

require "github/config/active_job"
require "github/config/aqueduct"
require "github/config/flipper"
require "flipper/vexi_proxy"
require "feature_flag/vexi"
require "github/faraday_adapter/persistent_excon"
require "active_job/queue_adapters/aqueduct_adapter"
require "github/logging/logfmt_formatter"
require_relative "instrumentation/jobs"
require_relative "../packages/admin/app/jobs/clean_up_old_business_member_invitations_job"
require_relative "../packages/admin/app/jobs/business_orchestration_sweeper_job"
require_relative "../packages/substrate/app/models/resiliency/response"

require_relative "../packages/billing/app/jobs/billing_job"
require_relative "../packages/branch_protections/app/jobs/ruleset_sweeper_job"
require_relative "../packages/gists/app/jobs/gist_maintenance_scheduler_job"
require_relative "../packages/gists/app/jobs/gist_purge_job"
require_relative "../packages/checks/app/jobs/checks_job_utility"
require_relative "../packages/checks/app/jobs/check_steps_orchestrate_deletion_job"
require_relative "../packages/checks/app/jobs/check_suites_archive_orchestration_job"
require_relative "../packages/checks/app/jobs/check_suites_delete_archived_orchestration_job"
require_relative "../packages/statuses/app/jobs/statuses_archive_orchestration_job"
require_relative "../packages/statuses/app/jobs/statuses_delete_archived_orchestration_job"
require_relative "../packages/code_scanning/app/jobs/code_scanning_kv_cleanup_expired_data_job"
require_relative "../packages/code_scanning/app/jobs/import_advanced_security_app_public_keys_job"
require_relative "../packages/planning/app/jobs/memex_kv_cleanup_expired_data_job"
require_relative "../packages/repositories/app/jobs/calculate_topic_applied_counts_job"
require_relative "../packages/repositories/app/jobs/remove_expired_announcements_job"
require_relative "../packages/repositories/app/jobs/repository_bulk_purge_job"
require_relative "../packages/repositories/app/jobs/repository_orchestration_sweeper_job"
require_relative "../packages/issues/app/jobs/issue_orchestration_sweeper_job"
require_relative "../packages/pull_requests/app/jobs/pull_request_orchestration_sweeper_job"
require_relative "../packages/security_products/app/jobs/security_campaigns/overdue_scheduler_job"
require_relative "../packages/security_products/app/jobs/security_center/dead_letter_job"
require_relative "../packages/security_products/app/jobs/security_center/kv_cleanup_expired_data_job"
require_relative "../app/jobs/audit_log_stream_health_checker_job"
require_relative "../app/jobs/memex_hydro_project_automation/instrumentation/shared"
require_relative "../app/jobs/memex_hydro_project_automation/instrumentation/scheduled_runner"
require_relative "../app/jobs/memex_project_workflow_scheduled_runner_job"
require_relative "../app/jobs/clean_locks_job"
require_relative "../app/jobs/billing/git_lfs_storage_metering_job"
require_relative "../packages/orgs/app/jobs/team_orchestration_sweeper_job"
require_relative "../packages/planning/app/jobs/purge_expired_memex_elasticsearch_consistency_scores_job"
require_relative "../packages/planning/app/jobs/report_memex_project_items_index_consistency_metric_job"
require_relative "../packages/planning/app/jobs/queue_memex_elasticsearch_resyncs_job"
require_relative "../packages/apps/app/jobs/proxima_app_sync/synchronize_first_party_apps_job"
require_relative "../packages/apps/app/jobs/proxima_app_sync/synchronize_third_party_apps_job"
require_relative "../packages/issues/app/jobs/dangling_issue_orchestration_starter_job"
require_relative "../packages/users/app/jobs/purge_orphaned_followers_job"
# This load private implementation of the job and the public helper exposing the class name of the job
require_relative "../packages/security_overview_analytics/app/public/security_overview_analytics/scheduler_job"
require_relative "../packages/discussions/app/jobs/discussions_kv_cleanup_expired_data_job"
require_relative "../packages/management_tools/app/jobs/feature_management_kv_cleanup_expired_data_job"
require_relative "../app/jobs/feeds_kv_cleanup_expired_data_job"
require_relative "../packages/users/app/jobs/users_kv_cleanup_expired_data_job"
require_relative "../packages/profiles/app/jobs/profiles_kv_cleanup_expired_data_job"
require_relative "../packages/security_products_enablement/app/jobs/security_products_enablement_kv_cleanup_expired_data_job"
require_relative "../app/jobs/connect_kv_cleanup_expired_data_job"
require_relative "../app/jobs/enterprise_accounts_kv_cleanup_expired_data_job"
require_relative "../app/jobs/orgs_kv_cleanup_expired_data_job"
require_relative "../app/jobs/organization_invitation_kv_cleanup_expired_data_job"
require_relative "../packages/stars/app/jobs/stars_kv_cleanup_expired_data_job"
require_relative "../app/jobs/site_kv_cleanup_expired_data_job"
require_relative "../packages/explore/app/jobs/explore_kv_cleanup_expired_data_job"
require_relative "../app/jobs/repository_advisories_kv_cleanup_expired_data_job"
require_relative "../app/jobs/apps_kv_cleanup_expired_data_job"
require_relative "../app/jobs/advisory_database_kv_cleanup_expired_data_job"
require_relative "../app/jobs/sponsors_kv_cleanup_expired_data_job"
require_relative "../app/jobs/teams_kv_cleanup_expired_data_job"
require_relative "../app/jobs/trust_safety_kv_cleanup_expired_data_job"
require_relative "../app/jobs/dependabot_kv_cleanup_expired_data_job"
require_relative "../app/jobs/mobile_kv_cleanup_expired_data_job"
require_relative "../app/jobs/external_identities_kv_cleanup_expired_data_job"
require_relative "../packages/management_tools/app/jobs/notices_kv_cleanup_expired_data_job"
require_relative "../app/jobs/clean_up_old_organization_invitations_job"
require_relative "../app/jobs/pages_kv_cleanup_expired_data_job"
require_relative "../packages/repositories/app/jobs/repositories_kv_cleanup_expired_data_job"
require_relative "../app/jobs/assets_kv_cleanup_expired_data_job"
require_relative "../app/jobs/marketplace_kv_cleanup_expired_data_job"
require_relative "../app/jobs/spokes_kv_cleanup_expired_data_job"
require_relative "../app/jobs/licensing_kv_cleanup_expired_data_job"
require_relative "../app/jobs/search_kv_cleanup_expired_data_job"
require_relative "../app/jobs/copilot_kv_cleanup_expired_data_job"
require_relative "../packages/spark_runtime/app/jobs/spark_runtime_kv_cleanup_expired_data_job"
require_relative "../packages/orgs/app/jobs/organization_orchestration_sweeper_job"

## Notifications jobs
require_relative "../packages/notifications/app/jobs/delete_expired_notifications_key_values_job"
require_relative "../packages/notifications/app/jobs/delete_expired_notification_summaries_tier1_job"
require_relative "../packages/notifications/app/jobs/delete_expired_notification_summaries_tier2_job"
require_relative "../packages/notifications/app/jobs/delete_expired_notification_summaries_tier3_job"
require_relative "../packages/notifications/app/jobs/delete_expired_notification_summaries_tier4_job"
require_relative "../packages/notifications/app/jobs/delete_expired_notification_summaries_tier5_job"

## Codespaces jobs
require_relative "../packages/codespaces/app/jobs/codespaces_job"
require_relative "../packages/codespaces/app/jobs/codespaces_kv_cleanup_job"
require_relative "../packages/codespaces/app/jobs/codespaces/suspend_stale_spark_workbench_codespaces_job"
require_relative "../packages/codespaces/app/jobs/codespaces_cache_skus_job"
require_relative "../packages/codespaces/app/jobs/codespaces_check_for_hung_async_operations_job"
require_relative "../packages/codespaces/app/jobs/codespaces_cleanup_unprocessed_billing_messages_job"
require_relative "../packages/codespaces/app/jobs/codespaces_fetch_billing_storage_account_names_dev_job"
require_relative "../packages/codespaces/app/jobs/codespaces_fetch_billing_storage_account_names_job"
require_relative "../packages/codespaces/app/jobs/codespaces_fetch_billing_storage_account_names_ppe_job"
require_relative "../packages/codespaces/app/jobs/codespaces/check_failover_status_job"
require_relative "../packages/codespaces/app/jobs/codespaces/check_for_shutdown_codespaces_job"
require_relative "../packages/codespaces/app/jobs/codespaces/enqueue_upcoming_template_job"
require_relative "../packages/codespaces/app/jobs/codespaces/past_retention_job"
require_relative "../packages/codespaces/app/jobs/codespaces/purge_soft_deleted_codespaces_job"
require_relative "../packages/codespaces/app/jobs/codespaces/upcoming_retention_notification_job"
require_relative "../packages/codespaces/app/jobs/codespaces/watch_orphaned_prebuild_templates_job"
require_relative "../packages/codespaces/app/jobs/codespaces/clean_up_stuck_provisioning_job"

require_relative "../packages/apps/app/jobs/cleanup_expired_permissions_job"

## Copilot jobs
require_relative "../packages/copilot/app/jobs/copilot_job"
require_relative "../packages/copilot/app/jobs/copilot/delete_orphaned_seats_job"
require_relative "../packages/copilot/app/jobs/copilot/pending_seat_assignments_job"
require_relative "../packages/copilot/app/jobs/copilot/seat_emission_job"
require_relative "../packages/copilot/app/jobs/copilot/billing/cleanup_non_emitting_orgs_job"
require_relative "../packages/copilot/app/jobs/copilot/billing/scheduled_plan_downgrade_job"
require_relative "../packages/copilot/app/jobs/copilot/billing/organizations/scheduled_plan_downgrade_job"
require_relative "../packages/copilot/app/jobs/copilot/chat_attachments/maintenance_job"
require_relative "../packages/copilot/app/jobs/copilot/seat_management/duplicate_seat_check_job"
require_relative "../packages/copilot/app/jobs/copilot/seat_management/team_sync_job"
require_relative "../packages/copilot/app/jobs/copilot/business_trials/status_check_job"


## Licensing jobs
require_relative "../packages/licensing/app/jobs/licensing/trigger_scheduled_licensing_model_transitions_job"
require_relative "../packages/licensing/app/jobs/licensing/trigger_scheduled_ghas_unbundle_transitions_job"

## Billing jobs
require_relative "../packages/billing/app/jobs/billing_expiring_card_reminders_job"
require_relative "../packages/billing/app/jobs/billing_update_exchange_rates_job"
require_relative "../packages/billing/app/jobs/billing/auth_and_capture/check_billable_entities_metered_usage_for_authorization_thresholds_job"
require_relative "../packages/billing/app/jobs/billing/azure/check_azure_subscriptions_job"
require_relative "../packages/billing/app/jobs/billing/check_payment_method_unique_number_identifier_reuse_over_threshold_job"
require_relative "../packages/billing/app/jobs/billing/check_unprocessed_sales_serve_webhooks_job"
require_relative "../packages/billing/app/jobs/billing/check_unprocessed_webhooks_job"
require_relative "../packages/billing/app/jobs/billing/check_unsuccessful_subscription_synchronizations_job"
require_relative "../app/jobs/perform_manual_dunning_period_job"
require_relative "../app/jobs/perform_ofac_downgrades_job"
require_relative "../packages/billing/app/jobs/perform_pending_plan_changes_job"
require_relative "../packages/billing/app/jobs/retrieve_failed_zuora_webhooks_job"
require_relative "../packages/billing/app/jobs/billing_kv_cleanup_job"
require_relative "../packages/billing/app/jobs/billing_run_start_job"
require_relative "../packages/billing/app/jobs/scheduled_azure_support_plan_sync_job"
require_relative "../packages/copilot4prs/app/jobs/pending_code_review_requests_sweeper_job"
require_relative "../packages/credit_decision_engine/app/public/credit_decision_engine"
require_relative "../packages/credit_decision_engine/app/jobs/credit_decision_engine/abstract_credit_check_status_poll_job"
require_relative "../packages/billing/app/jobs/credit_check_status_poll_job"

# configure ActiveJob
ActiveJob::Base.queue_adapter = :aqueduct

logger = ActiveSupport::Logger.new(STDOUT)
logger.level = ::Logger::INFO
logger.formatter = ::GitHub::Logging::LogfmtFormatter.new(GitHub::Logger.default_log_data.merge(ns: "timer_daemon"))
ActiveJob::Base.logger = ActiveSupport::TaggedLogging.new(logger)

# configure daemon
daemon = TimerDaemon.instance
daemon.redis = GitHub.legacy_redis
scheduler = JobScheduler.new(daemon)

# report exceptions to Failbot
daemon.error do |boom, timer|
  Failbot.report(boom, timer: timer.name)
end

daemon.schedule "timerd-heartbeat-proxima-global", 10.seconds do
  GitHub.dogstats.increment "timerd.heartbeat", tags: ["config:proxima", "scope:global"]
end

daemon.schedule "timerd-heartbeat-proxima-host", 10.seconds, scope: :host do
  GitHub.dogstats.increment "timerd.heartbeat", tags: ["config:proxima", "scope:host"]
end

[
  CalculateTopicAppliedCountsJob,
  DeleteExpiredReservedLoginTombstonesJob,

  NetworkMaintenanceSchedulerJob,
  DanglingIssueOrchestrationStarterJob,
  RepositoryOrchestrationSweeperJob,
  IssueOrchestrationSweeperJob,
  PullRequestOrchestrationSweeperJob,
  QueueMediaTransitionJobsJob,
  RepositoryBulkPurgeJob,
  RemoveExpiredOauthJob,
  RulesetSweeperJob,

  # Storage archiving and purging
  PurgeArchivedAssetsJob,
  PurgeRestorablesJob,

  WikiMaintenanceSchedulerJob,

  # Git Backups
  GitbackupsSchedulerJob,
  GitbackupsSweeperJob,
  GitbackupsEnsureFreshKeyJob,

  # Supply Chain
  DependabotSecurityUpdateTimeoutCleanupJob,
  EnterpriseAdvisoryDatabaseSyncJob,

  # code scanning
  StaleCodeScanningCheckRunsScheduledJob,
  ImportAdvancedSecurityAppPublicKeysJob,
  SecurityCampaigns::OverdueSchedulerJob,
  CodeScanningKvCleanupExpiredDataJob,

  QueueCollectMetricsJob,

  # feature-management
  StaleCheckJob,

  # Invalidate expired invitations
  InvalidateExpiredInvitesJob,
  ExpireBusinessAdminInvitationsJob,
  ExpireBusinessOrganizationInvitationsJob,
  SendBusinessOrganizationInvitationRemindersJob,
  CleanUpOldOrganizationInvitationsJob,
  CleanUpOldBusinessMemberInvitationsJob,

  # Migration storage monitoring
  OctoshiftStorageMonitoringJob,

  # Advanced Security
  MeteredAdvancedSecurityScheduledEmitterJob,

  # Authentication
  AuthenticationKvCleanupExpiredDataJob,

  # Audit Log
  AuditLogStreamHealthCheckerJob,

  # KV Cleanup
  GrowthNoticeKvCleanupExpiredDataJob,
  GrowthLastActivityKvCleanupExpiredDataJob,
  FeedsKvCleanupExpiredDataJob,
  ConnectKvCleanupExpiredDataJob,
  EnterpriseAccountsKvCleanupExpiredDataJob,
  OrgsKvCleanupExpiredDataJob,
  OrganizationInvitationKvCleanupExpiredDataJob,
  SiteKvCleanupExpiredDataJob,
  RepositoryAdvisoriesKvCleanupExpiredDataJob,
  AppsKvCleanupExpiredDataJob,
  AdvisoryDatabaseKvCleanupExpiredDataJob,
  SponsorsKvCleanupExpiredDataJob,
  TeamsKvCleanupExpiredDataJob,
  TrustSafetyKvCleanupExpiredDataJob,
  ExternalIdentitiesKvCleanupExpiredDataJob,
  DependabotKvCleanupExpiredDataJob,
  PagesKvCleanupExpiredDataJob,
  MobileKvCleanupExpiredDataJob,
  AssetsKvCleanupExpiredDataJob,
  MarketplaceKvCleanupExpiredDataJob,
  SpokesKvCleanupExpiredDataJob,
  LicensingKvCleanupExpiredDataJob,
  SearchKvCleanupExpiredDataJob,
  CopilotKvCleanupExpiredDataJob,

  # PAT Expiry Emails
  PersonalTokenExpiryNoticeJob,
  PersonalTokenExpiredNoticeJob,

  # PAT Request Notices
  NotifyOrgAdminsAboutPatRequestsJob,

  # Proxima App Sync
  ProximaAppSync::SynchronizeFirstPartyAppsJob,
  ProximaAppSync::SynchronizeThirdPartyAppsJob,

  # EMUs
  ScanEmuExternalTeamsJob,
  ScanEmuOrganizationMembershipsJob,
  ScanEmuOrganizationUsersJob,

  # Enterprise accounts
  BusinessTrialExpirationJob,
  BusinessTrialRestoreUpgradeStateJob,
  NotifyExpiredTrialsJob,
  DeleteExpiredTrialsJob,
  BusinessReportExportsCleanupJob,
  PurgeSoftDeletedBusinessesJob,
  PurgeCancelledTrialsJob,
  BusinessOrchestrationSweeperJob,

  # Organizations
  OrganizationOrchestrationSweeperJob,

  # Expiring announcements
  RemoveExpiredAnnouncementsJob,

  # Teams
  CleanUpDeletedTeamsJob,
  TeamOrchestrationSweeperJob,

  # Projects
  PurgeDeletedMemexProjectsJob,
  MemexKvCleanupExpiredDataJob,

  # Actions & Checks
  CheckStepsOrchestrateDeletionJob,
  CheckSuitesArchiveOrchestrationJob,
  CheckSuitesDeleteArchivedOrchestrationJob,
  StatusesArchiveOrchestrationJob,
  StatusesDeleteArchivedOrchestrationJob,
  ActionsKvCleanupExpiredDataJob,

  # Dependabot alerts digest
  NewsletterDeliveryJob,

  # Scheduled reminders
  EnqueueUpcomingRemindersJob,

  # Distributed progress tracking
  StopAllStalledProgressJob,

  # Memex Automation
  MemexProjectWorkflowScheduledRunnerJob,

  # Memex Project items index consistency metrics
  ReportMemexProjectItemsIndexConsistencyMetricJob,
  QueueMemexElasticsearchResyncsJob,

  # Security Center Analytics
  SecurityOverviewAnalytics::SchedulerJob,

  # Security Center
  SecurityCenter::DeadLetterJob,
  SecurityProductsEnablementKvCleanupExpiredDataJob,
  SecurityCenter::KvCleanupExpiredDataJob,

  # User cleanup
  PurgeOrphanedFollowersJob,

  ###
  # Notifications
  ###
  # clean up expired entries on notification_key_values table
  DeleteExpiredNotificationsKeyValuesJob,
  DeleteExpiredNotificationSummariesTier1Job,
  DeleteExpiredNotificationSummariesTier2Job,
  DeleteExpiredNotificationSummariesTier3Job,
  DeleteExpiredNotificationSummariesTier4Job,
  DeleteExpiredNotificationSummariesTier5Job,

  # Platform Health
  SpamKvCleanupJob,

  # Billing
  BillingKvCleanupJob,
  Billing::GitLfsStorageMeteringJob,
  ScheduledAzureSupportPlanSyncJob,
  BillingUpdateExchangeRatesJob,
  Billing::Azure::CheckAzureSubscriptionsJob,
  CreditCheckStatusPollJob,
  PerformOFACDowngradesJob,
  PerformManualDunningPeriodJob,
  BillingExpiringCardRemindersJob,
  BillingRunStartJob,
  Billing::CheckUnprocessedWebhooksJob,
  Billing::CheckUnprocessedSalesServeWebhooksJob,
  Billing::CheckUnsuccessfulSubscriptionSynchronizationsJob,
  PerformPendingPlanChangesJob,
  Billing::CheckPaymentMethodUniqueNumberIdentifierReuseOverThresholdJob,
  Billing::AuthAndCapture::CheckBillableEntitiesMeteredUsageForAuthorizationThresholdsJob,
  RetrieveFailedZuoraWebhooksJob,

  # Job system cleanup
  CleanLocksJob,

  # Signup Flow
  SignupFlowKvCleanupExpiredDataJob,

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

  # GitHub Apps
  CleanupExpiredPermissionsJob,

  # Copilot
  # Don't forget to add require_relative at the top for these classes
  Copilot::DeleteOrphanedSeatsJob,
  Copilot::SeatEmissionJob,
  Copilot::PendingSeatAssignmentsJob,
  Copilot::Billing::CleanupNonEmittingOrgsJob,
  Copilot::Billing::ScheduledPlanDowngradeJob,
  Copilot::Billing::Organizations::ScheduledPlanDowngradeJob,
  Copilot::BusinessTrials::StatusCheckJob,
  Copilot::ChatAttachments::MaintenanceJob,
  Copilot::SeatManagement::TeamSyncJob,
  Copilot::SeatManagement::DuplicateSeatCheckJob,
  PendingCodeReviewRequestsSweeperJob,

  # Discussions
  DiscussionsKvCleanupExpiredDataJob,

  # Feature Management
  FeatureManagementKvCleanupExpiredDataJob,

  # Licensing
  Licensing::TriggerScheduledLicensingModelTransitionsJob,
  Licensing::TriggerScheduledGhasUnbundleTransitionsJob,

  UsersKvCleanupExpiredDataJob,
  ProfilesKvCleanupExpiredDataJob,
  StarsKvCleanupExpiredDataJob,
  ExploreKvCleanupExpiredDataJob,
  NoticesKvCleanupExpiredDataJob,
  RepositoriesKvCleanupExpiredDataJob,
  SparkRuntimeKvCleanupExpiredDataJob,
].each do |job|
  scheduler.schedule job
end

# Pages
scheduler.schedule "DeleteDependentPagesReplicasSchedulerJob", interval: 1.day, scope: :global
scheduler.schedule "DpagesEvacuationSchedulerJob", interval: 3.minutes
scheduler.schedule "DpagesMaintenanceSchedulerJob", interval: GitHub.dpages_maintenance_scheduler_schedule_interval
scheduler.schedule "PageUpdatesJob", interval: 1.minute, condition: -> { PageUpdatesJob.enabled? }

# GitHub Apps
scheduler.schedule "CleanupOrphanedBotsJob", interval: 7.days

# Billing
scheduler.schedule "Billing::DailyCustomerWithoutPaymentInformationDunningCheckJob", interval: 1.hour

# Advanced Security
scheduler.schedule "AdvancedSecurity::LockMeteredUsageScheduledJob", interval: 1.day, condition: -> { !GitHub.enterprise? }
scheduler.schedule "AdvancedSecurity::UnlockMeteredUsageScheduledJob", interval: 10.minutes, condition: -> { !GitHub.enterprise? }

# Projects
scheduler.schedule "PurgeExpiredMemexElasticsearchConsistencyScoresJob", interval: 1.day
