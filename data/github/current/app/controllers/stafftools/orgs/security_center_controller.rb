# typed: true
# frozen_string_literal: true

require "github/security_center/logging_helper"

class Stafftools::Orgs::SecurityCenterController < StafftoolsController
  include GitHub::SecurityCenter::LoggingHelper

  Initialization = ::SecurityOverviewAnalytics::Initialization
  Fanout = ::SecurityOverviewAnalytics::Fanout

  before_action :ensure_org_not_user
  before_action :ensure_user_exists
  before_action :dotcom_required # limiting to dotcom so only GitHub staff can access

  around_action :set_log_context

  layout "layouts/stafftools/organization/overview"

  def show
    locals = {
      organization: current_organization,
      reconciliation_cache: {
        key: reconciliation_kv.session_key,
        ttl: reconciliation_kv.session_ttl,
      },
      security_manager_teams: security_manager_teams,
      analytics: {
        eligible?: ::SecurityOverviewAnalytics::TenantValidationHelper.is_owner_in_scope?(current_organization),
        metrics: [
          Initialization::Type::RepositoryMetadata,
          Initialization::Type::FeatureEnablement,
          Initialization::Type::DependabotAlerts,
          Initialization::Type::CodeScanningAlert,
          Initialization::Type::SecretScanningAlert,
          Fanout::Types::Feature::CodeScanningPullRequestAlert,
        ].map(&:serialize)
      },
    }

    render "stafftools/organizations/security_center", locals: { **locals }
  end

  def analytics # rubocop:todo GitHub/UseRestfulActions
    metric = params[:metric]
    return render_404 if metric.nil?

    metric_type = Initialization::Type.try_deserialize(metric) || Fanout::Types::Feature.try_deserialize(metric)
    return render_404 if metric_type.nil?

    initialization = Initialization.for(current_organization)

    metric_stats = case metric_type
    when Initialization::Type::RepositoryMetadata
      analytics_repo_stats(initialization)
    when Initialization::Type::FeatureEnablement
      analytics_feature_stats(initialization)
    when Initialization::Type::DependabotAlerts
      analytics_alerts_stats(::SecurityOverviewAnalytics::DependabotAlertRevision, Initialization::Type::DependabotAlerts, initialization)
    when Initialization::Type::CodeScanningAlert
      analytics_alerts_stats(::SecurityOverviewAnalytics::CodeScanningAlertRevision, Initialization::Type::CodeScanningAlert, initialization)
    when Initialization::Type::SecretScanningAlert
      analytics_alerts_stats(::SecurityOverviewAnalytics::SecretScanningAlertRevision, Initialization::Type::SecretScanningAlert, initialization)
    when Fanout::Types::Feature::CodeScanningPullRequestAlert
      analytics_pull_request_stats
    else
      nil
    end
    return render_404 if metric_stats.nil?

    render partial: "stafftools/organizations/security_center/analytics", locals: { **{ stats: metric_stats } }
  end

  def code_scanning_alert_counts # rubocop:todo GitHub/UseRestfulActions
    locals = {
      open_alerts: code_scanning_open_alerts_count,
      open_analytics_alerts: soa_total_open_alert_counts_by_feature[:code_scanning],
      closed_alerts: code_scanning_closed_alerts_count,
      total_alerts: code_scanning_open_alerts_count + code_scanning_closed_alerts_count,
      feature_name: "code_scanning",
    }

    render partial: "stafftools/organizations/security_center/alert_counts", locals: { **locals }
  end

  def dependabot_alert_counts # rubocop:todo GitHub/UseRestfulActions
    locals = {
      open_alerts: dependabot_open_alerts_count,
      open_analytics_alerts: soa_total_open_alert_counts_by_feature[:dependabot_alerts],
      closed_alerts: dependabot_closed_alerts_count,
      total_alerts: dependabot_total_alerts_count,
      feature_name: "dependabot_alerts",
    }

    render partial: "stafftools/organizations/security_center/alert_counts", locals: { **locals }
  end

  def secret_scanning_alert_counts # rubocop:todo GitHub/UseRestfulActions
    locals = {
      open_alerts: secret_scanning_open_alerts_count,
      open_analytics_alerts: soa_total_open_alert_counts_by_feature[:secret_scanning],
      closed_alerts: secret_scanning_closed_alerts_count,
      total_alerts: secret_scanning_open_alerts_count + secret_scanning_closed_alerts_count,
      feature_name: "secret_scanning",
    }

    render partial: "stafftools/organizations/security_center/alert_counts", locals: { **locals }
  end

  def trigger_reconciliation_job # rubocop:todo GitHub/UseRestfulActions
    source_event = "security_center.stafftools.reconciliation"
    SecurityCenter::OwnerReconciliationJob.perform_later(owner_id: current_organization.id, source_event: source_event)
    GitHub.logger.info(
      "Queued reconciliation job from stafftools",
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.security_center.source_event": source_event,
    )

    redirect_to stafftools_user_security_center_path(current_organization), flash: { notice: "Reconciliation job scheduled." }
  end

  def initialize_analytics # rubocop:todo GitHub/UseRestfulActions
    feature_type = params[:type]

    if feature_type.nil?
      ::SecurityOverviewAnalytics::FanoutScheduler.initialize_for(current_organization)
      Initialization.for(current_organization).enqueue(type: nil)
    else
      type = Initialization::Type.try_deserialize(feature_type)
      Initialization.for(current_organization).enqueue(type:)
    end

    log_info(
      "Queued analytics initialization job from stafftools",
      "gh.security_overview_analytics.initialization_type": feature_type || "all"
    )
    redirect_to stafftools_user_security_center_path(current_organization), flash: { notice: "Analytics initialization scheduled." }
  end

  def reset_analytics # rubocop:todo GitHub/UseRestfulActions
    type = params[:type] ? Initialization::Type.deserialize(params[:type]) : nil
    Initialization::BatchedResetJob.perform_later(organization_ids: [current_organization.id], include_private_beta: true, type: type&.serialize)

    log_info(
      "Queued analytics reset job from stafftools",
      "gh.security_overview_analytics.initialization_type": type&.serialize || "all",
    )

    redirect_to stafftools_user_security_center_path(current_organization), flash: { notice: "Analytics reset scheduled." }
  end

  def enqueue_analytics_reconciliation # rubocop:todo GitHub/UseRestfulActions
    feature_type = params[:type]

    if feature_type.nil?
      ::SecurityOverviewAnalytics::FanoutScheduler.reconcile_for(current_organization)
      SecurityOverviewAnalytics::Reconciliation::OrganizationReconciliationJob.perform_later(organization_id: current_organization.id, type: nil)
    else
      type = Initialization::Type.try_deserialize(feature_type)
      SecurityOverviewAnalytics::Reconciliation::OrganizationReconciliationJob.perform_later(organization_id: current_organization.id, type: type&.serialize)
    end

    log_info(
      "Queued analytics reconciliation job from stafftools",
      "gh.security_overview_analytics.initialization_type": feature_type || "all",
    )
    redirect_to stafftools_user_security_center_path(current_organization), flash: { notice: "Scheduled analytics reconciliation." }
  end

  def clear_analytics_reconciliation # rubocop:todo GitHub/UseRestfulActions
    feature_type = params[:type]
    if feature_type
      if fanout_feature = Fanout::Types::Feature.try_deserialize(feature_type)
        Fanout::Session.new(
          action: Fanout::Types::Action::Reconcile,
          tenant_scope: Fanout::Types::TenantScope::Organization,
          tenant_id: current_organization.id,
          feature: fanout_feature,
          feature_prerequisite: nil,
          expires: nil
        ).unlock!
        log_info(
          "Cleared analytics reconciliation lock from stafftools",
          "gh.security_overview_analytics.initialization_type": fanout_feature,
        )
      else
        type = Initialization::Type.deserialize(params[:type])
        session = SecurityOverviewAnalytics::Reconciliation::Session.new(owner_id: current_organization.id, type: type.serialize)
        session.reset!(last_session_started_at: nil)
        log_info(
          "Cleared analytics reconciliation lock from stafftools",
          "gh.security_overview_analytics.initialization_type": type,
        )
      end

      message = "Cleared analytics reconciliation lock."
    else
      message = "Resetting reconciliation failed."
      log_info(
        "Passed in nil for session type",
      )
    end

    redirect_to stafftools_user_security_center_path(current_organization), flash: { notice: message }
  end

  private

  memoize def current_organization
    this_user
  end

  def set_log_context
    GitHub.logger.with_named_tags(
      "enduser.id": current_user.display_login,
      "gh.enduser.id": current_user.id,
      "gh.org.id": current_organization.id,
      "gh.org.login": current_organization.display_login,
    ) do
      yield
    end
  end

  memoize def reconciliation_kv
    ::SecurityCenter::OwnerReconciliationJob::KvHelper.new(current_organization.id)
  end

  def security_manager_teams
    SecurityProduct::SecurityManagers.new(current_organization).teams
  end

  memoize def code_scanning_alert_info
    GitHub::Turboscan.alerts_by_repo(
      owner_ids: [current_organization.id],
      limit: 1,
    )&.data
  end

  def code_scanning_open_alerts_count
    code_scanning_alert_info&.open_count || 0
  end

  def code_scanning_closed_alerts_count
    code_scanning_alert_info&.resolved_count || 0
  end

  def code_scanning_total_alerts_count
    code_scanning_open_alerts_count + code_scanning_closed_alerts_count
  end

  memoize def dependabot_alerts_query
    user = current_organization.direct_admins.first
    RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(organization: current_organization, user: user, user_session: user_session)
  end

  def dependabot_open_alerts_count
    dependabot_alerts_query.open_count
  end

  def dependabot_closed_alerts_count
    dependabot_alerts_query.closed_count
  end

  def dependabot_total_alerts_count
    dependabot_alerts_query.count
  end

  memoize def secret_scanning_alert_info
    user = current_organization.direct_admins.first
    SecretScanning::AlertQueryService.for_organization(organization: current_organization, current_user: user, user_session: user_session).get_alerts
  end

  def secret_scanning_open_alerts_count
    alerts, open_alert_count, closed_alert_count, _, request_error = secret_scanning_alert_info
    open_alert_count || 0
  end

  def secret_scanning_closed_alerts_count
    alerts, open_alert_count, closed_alert_count, _, request_error = secret_scanning_alert_info
    closed_alert_count || 0
  end

  memoize def soa_total_open_alert_counts_by_feature
    SecurityOverviewAnalytics::Risk::TabCountsQuery
      .for_organization(
        organization: current_organization,
        user: T.must(current_user),
        user_session: user_session,
        parser: ::Search::Queries::SecurityCenter::RiskQueryParser.new(""),
      )
      .perform
  end

  def analytics_repo_stats(initialization)
    metric_type = Initialization::Type::RepositoryMetadata
    reconciliation_session = ::SecurityOverviewAnalytics::Reconciliation::Session.new(owner_id: current_organization.id, type: metric_type.serialize)

    current_count = ::SecurityOverviewAnalytics::Repository
      .where(owner_id: current_organization.id)
      .count

    {
      metric_type: metric_type.serialize,
      current_count:,
      initialized?: initialization.initialized?(type: metric_type),
      last_reconciled: reconciliation_session.session_started_at,
      reconciliation_locked?: reconciliation_session.locked?,
      reconciliation_lock_expiry: reconciliation_session.ttl,
    }
  end

  def analytics_feature_stats(initialization)
    metric_type = Initialization::Type::FeatureEnablement
    reconciliation_session = ::SecurityOverviewAnalytics::Reconciliation::Session.new(owner_id: current_organization.id, type: metric_type.serialize)

    revisions_rel = ::SecurityOverviewAnalytics::FeatureStatusRevision
      .joins(:repository_metadata)
      .where(repository_metadata: { owner_id: current_organization.id })

    revision_count = revisions_rel.count
    current_count = revisions_rel
      .where(next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID)
      .count

    {
      metric_type: metric_type.serialize,
      revision_count:,
      current_count:,
      initialized?: initialization.initialized?(type: metric_type),
      last_reconciled: reconciliation_session.session_started_at,
      reconciliation_locked?: reconciliation_session.locked?,
      reconciliation_lock_expiry: reconciliation_session.ttl,
    }
  end

  def analytics_alerts_stats(model, metric_type, initialization)
    reconciliation_session = ::SecurityOverviewAnalytics::Reconciliation::Session.new(owner_id: current_organization.id, type: metric_type.serialize)

    revisions_rel = model
      .joins(:repository_metadata)
      .where(repository_metadata: { owner_id: current_organization.id })

    revision_count = revisions_rel.count
    current_counts_by_state = revisions_rel
      .where(next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID)
      .select(
        Arel.sql("SUM(IF(#{model.table_name}.alert_resolved = 1, 1, 0)) as total_alerts_resolved"),
        Arel.sql("SUM(IF(#{model.table_name}.alert_resolved = 0, 1, 0)) as total_alerts_open")
      )
      .first
    current_closed_count = current_counts_by_state&.total_alerts_resolved&.to_i || 0
    current_open_count = current_counts_by_state&.total_alerts_open&.to_i || 0
    current_count = current_open_count + current_closed_count

    {
      metric_type: metric_type.serialize,
      revision_count:,
      current_count:,
      current_open_count:,
      current_closed_count:,
      initialized?: initialization.initialized?(type: metric_type),
      last_reconciled: reconciliation_session.session_started_at,
      reconciliation_locked?: reconciliation_session.locked?,
      reconciliation_lock_expiry: reconciliation_session.ttl,
    }
  end

  def analytics_pull_request_stats
    feature = Fanout::Types::Feature::CodeScanningPullRequestAlert

    initialization_session = Fanout::Session.new(
      action: Fanout::Types::Action::Initialize,
      tenant_scope: Fanout::Types::TenantScope::Organization,
      tenant_id: current_organization.id,
      feature:,
      feature_prerequisite: nil,
      expires: nil
    )
    reconciliation_session = Fanout::Session.new(
      action: Fanout::Types::Action::Reconcile,
      tenant_scope: Fanout::Types::TenantScope::Organization,
      tenant_id: current_organization.id,
      feature:,
      feature_prerequisite: nil,
      expires: nil
    )

    model = ::SecurityOverviewAnalytics::CodeScanningPullRequestAlert
    current_counts_by_state = model
      .joins(:repository_metadata)
      .where(repository_metadata: { owner_id: current_organization.id })
      .select(
        Arel.sql("SUM(IF(#{model.table_name}.alert_resolved = 1, 1, 0)) as total_alerts_resolved"),
        Arel.sql("SUM(IF(#{model.table_name}.alert_resolved = 0, 1, 0)) as total_alerts_open")
      )
      .first
    current_closed_count = current_counts_by_state&.total_alerts_resolved&.to_i || 0
    current_open_count = current_counts_by_state&.total_alerts_open&.to_i || 0
    current_count = current_open_count + current_closed_count

    {
      metric_type: feature.serialize,
      current_count:,
      current_open_count:,
      current_closed_count:,
      initialized?: initialization_session.locked?,
      last_reconciled: reconciliation_session.locked_at,
      reconciliation_locked?: reconciliation_session.locked?,
      reconciliation_lock_expiry: reconciliation_session.ttl,
      global_fanout_only: true,
    }
  end

  depends_on_clusters \
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    only: [
      :analytics,
      :code_scanning_alert_counts,
      :dependabot_alert_counts,
      :secret_scanning_alert_counts,
      :show,
    ]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [
      :analytics,
      :code_scanning_alert_counts,
      :dependabot_alert_counts,
      :secret_scanning_alert_counts,
      :show,
    ],
    optional: true
end
