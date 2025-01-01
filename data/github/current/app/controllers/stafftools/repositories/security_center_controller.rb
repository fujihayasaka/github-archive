# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::SecurityCenterController < StafftoolsController

  before_action :dotcom_required # limiting to dotcom so only GitHub staff can access
  before_action :ensure_repo_exists
  before_action :ensure_org_owned_repository

  around_action :set_log_context

  layout "layouts/stafftools/repository/overview"

  depends_on_clusters \
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::SecurityOverviewAnalytics,
    ApplicationRecord::Spokes,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render "stafftools/repositories/security_center", locals: {
      conflicts: detect_conflicts,
      config: sc_config,
      statuses: sc_statuses,
      severities: sc_alert_severities,
      alert_counts: {
        code_scanning: {
          open: code_scanning_open_alerts_count,
          closed: code_scanning_closed_alerts_count,
          total: code_scanning_open_alerts_count + code_scanning_closed_alerts_count,
        },
        dependabot: {
          open: dependabot_open_alerts_count,
          closed: dependabot_closed_alerts_count,
          total: dependabot_total_alerts_count,
        },
        secret_scanning: {
          open: secret_scanning_open_alerts_count,
          closed: secret_scanning_closed_alerts_count,
          total: secret_scanning_open_alerts_count + secret_scanning_closed_alerts_count,
        },
      },
      analytics_data:,
    }
  end

  def trigger_update_job # rubocop:todo GitHub/UseRestfulActions
    feature_type = SecurityCenter::RepositorySyncJob::ALL_FEATURES_TYPE
    source_event = "security_center.stafftools.update_repo"
    SecurityCenter::RepositorySyncJob.perform_later(repository_id: current_repository.id, feature_type: feature_type, source_event: source_event)
    GitHub.logger.info(
      "Queued update job from stafftools",
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.security_center.feature_type": feature_type,
      "gh.security_center.source_event": source_event,
    )

    redirect_to security_center_stafftools_repository_path(current_repository.owner, current_repository), flash: { notice: "Update job scheduled." }
  end

  private

  def ensure_org_owned_repository
    render_404 unless this_user.organization?
  end

  def set_log_context
    GitHub.logger.with_named_tags(
      "enduser.id": current_user.display_login,
      "gh.enduser.id": current_user.id,
      "gh.repo.id": current_repository.id,
      "gh.repo.name": current_repository.name,
      "gh.owner.id": current_repository.owner_id,
      "gh.owner.login": current_repository.owner_display_login,
    ) do
      yield
    end
  end

  def detect_conflicts
    [].tap do |conflicts|
      # RepositorySecurityCenterConfig vs Repository
      if sc_config.present?
        conflicts << "Name in RepositorySecurityCenterConfig (#{sc_config.name}) doesn't match" if current_repository.name != sc_config.name
        conflicts << "\"Advanced security enabled\" in RepositorySecurityCenterConfig (#{sc_config.ghas_enabled}) doesn't match repo's current value (#{current_repository.advanced_security_enabled?})" if sc_config.ghas_enabled != current_repository.advanced_security_enabled?
        conflicts << "\"Visibility\" in RepositorySecurityCenterConfig (#{sc_config.visibility}) doesn't match repo's current value (#{current_repository.visibility})" if sc_config.visibility != current_repository.visibility
        conflicts << "\"Archived\" in RepositorySecurityCenterConfig (#{sc_config.archived}) doesn't match repo's current value (#{current_repository.archived?})" if sc_config.archived != current_repository.archived?
        conflicts << "\"Last code push at\" in RepositorySecurityCenterConfig (#{sc_config.last_push}) doesn't match repo's current value (#{current_repository.pushed_at})" if sc_config.last_push.to_i != current_repository.pushed_at.to_i
      end

      # RepositorySecurityCenterStatus vs Code Scanning
      cs_status = sc_statuses.where(feature_type: "code_scanning").first
      if cs_status.present?
        conflicts << "Code scanning open alerts count in RepositorySecurityCenterStatus (#{cs_status.scanning_count}) doesn't match Turboscan's value (#{code_scanning_open_alerts_count})" if cs_status.scanning_count != code_scanning_open_alerts_count
      end

      # SecurityCenterAlertSeverity vs Code Scanning
      sev_cs = code_scanning_alert_counts_by_severity
      sev_cs_sc = sc_alert_severities.where(feature_type: "code_scanning").group(:severity).count

      if sev_cs_sc.present?
        sev_diff_1 = sev_cs.keys - sev_cs_sc.keys
        conflicts << "Code scanning has severity categories not in SecurityCenterAlertSeverity: #{sev_diff_1}" unless sev_diff_1.empty?
        sev_diff_2 = sev_cs_sc.keys - sev_cs.keys
        conflicts << "SecurityCenterAlertSeverity has severity categories not in code scanning: #{sev_diff_2}" unless sev_diff_2.empty?

        sev_diff_1.each do |severity, _count|
          conflicts << "Code scanning #{severity} count in SecurityCenterAlertSeverity (#{sev_cs_sc[severity]}) doesn't match code scanning's value (#{sev_cs[severity]})" if sev_cs[severity] != sev_cs_sc[severity]
        end
      end

      # RepositorySecurityCenterStatus vs Dependabot Alerts
      dbot_status = sc_statuses.where(feature_type: "dependabot_alerts").first
      if dbot_status.present?
        conflicts << "Dependabot open alerts count in RepositorySecurityCenterStatus (#{dbot_status.scanning_count}) doesn't match Dependabot Alert's value (#{dependabot_open_alerts_count})" if dbot_status.scanning_count != dependabot_open_alerts_count
      end

      # SecurityCenterAlertSeverity vs Dependabot Alerts
      sev_dbot = dependabot_alert_counts_by_severity
      sev_dbot_sc = sc_alert_severities.where(feature_type: "dependabot_alerts").group(:severity).count

      if sev_dbot_sc.present?
        sev_diff_1 = sev_dbot.keys - sev_dbot_sc.keys
        conflicts << "Dependabot alerts has severity categories not in SecurityCenterAlertSeverity: #{sev_diff_1}" unless sev_diff_1.empty?
        sev_diff_2 = sev_dbot_sc.keys - sev_dbot.keys
        conflicts << "SecurityCenterAlertSeverity has severity categories not in Dependabot alerts: #{sev_diff_2}" unless sev_diff_2.empty?

        sev_diff_1.each do |severity, _count|
          conflicts << "Dependabot alerts #{severity} count in SecurityCenterAlertSeverity (#{sev_dbot_sc[severity]}) doesn't match Dependabot alert's value (#{sev_dbot[severity]})" if sev_dbot[severity] != sev_dbot_sc[severity]
        end
      end

      # RepositorySecurityCenterStatus vs Secret Scanning
      ss_status = sc_statuses.where(feature_type: "secret_scanning").first
      if ss_status.present?
        conflicts << "Secret scanning open alerts count in RepositorySecurityCenterStatus (#{ss_status.scanning_count}) doesn't match Token Scanning Service's value (#{secret_scanning_open_alerts_count})" if ss_status.scanning_count != secret_scanning_open_alerts_count
      end
    end
  end

  memoize def sc_config
    RepositorySecurityCenterConfig.find_by(repository_id: current_repository.id)
  end

  memoize def sc_statuses
    RepositorySecurityCenterStatus.where(repository_id: current_repository.id)
  end

  memoize def sc_alert_severities
    SecurityCenterAlertSeverity.where(repository_id: current_repository.id)
  end

  memoize def secret_scanning_alert_info
    SecretScanning::AlertQueryService.for_repository(repository: current_repository, current_user: current_user).get_alerts
  end

  def secret_scanning_open_alerts_count
    alerts, open_alert_count, closed_alert_count, _, request_error = secret_scanning_alert_info
    open_alert_count
  end

  def secret_scanning_closed_alerts_count
    alerts, open_alert_count, closed_alert_count, _, request_error = secret_scanning_alert_info
    closed_alert_count
  end

  memoize def code_scanning_alert_info
    GitHub::Turboscan.alerts_by_repo(
      owner_ids: [current_repository.owner_id],
      repository_ids: [current_repository.id],
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

  memoize def code_scanning_alert_counts_by_severity
    current_repository.code_scanning_open_alerts_count_by_severity
  end

  memoize def dependabot_alerts_query
    RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(repository: current_repository)
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

  def dependabot_alert_counts_by_severity
    dependabot_alerts_query.open.repository_alert_count_by_severity(repository_ids: [current_repository.id])
      .transform_keys { |key| key.second }
  end

  def analytics_data
    initialization = ::SecurityOverviewAnalytics::Initialization.for(this_user)

    {
      eligible?: ::SecurityOverviewAnalytics::TenantValidationHelper.is_owner_in_scope?(this_user),
      metric_types: [
        analytics_repo_stats(initialization),
        analytics_feature_stats(initialization),
        analytics_alerts_stats(::SecurityOverviewAnalytics::DependabotAlertRevision, ::SecurityOverviewAnalytics::Initialization::Type::DependabotAlerts, initialization),
        analytics_alerts_stats(::SecurityOverviewAnalytics::CodeScanningAlertRevision, ::SecurityOverviewAnalytics::Initialization::Type::CodeScanningAlert, initialization),
        analytics_alerts_stats(::SecurityOverviewAnalytics::SecretScanningAlertRevision, ::SecurityOverviewAnalytics::Initialization::Type::SecretScanningAlert, initialization),
      ]
    }
  end

  def analytics_repo_stats(initialization)
    metric_type = ::SecurityOverviewAnalytics::Initialization::Type::RepositoryMetadata
    reconciliation_session = ::SecurityOverviewAnalytics::Reconciliation::Session.new(owner_id: this_user.id, type: metric_type.serialize)

    {
      metric_type: metric_type.serialize,
      initialized?: initialization.initialized?(type: metric_type),
      last_reconciled: reconciliation_session.session_started_at,
      reconciliation_locked?: reconciliation_session.locked?,
      reconciliation_lock_expiry: reconciliation_session.ttl,
    }
  end

  def analytics_feature_stats(initialization)
    metric_type = ::SecurityOverviewAnalytics::Initialization::Type::FeatureEnablement
    reconciliation_session = ::SecurityOverviewAnalytics::Reconciliation::Session.new(owner_id: this_user.id, type: metric_type.serialize)

    revisions_rel = ::SecurityOverviewAnalytics::FeatureStatusRevision
      .where(repository_id: current_repository.id)

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
    reconciliation_session = ::SecurityOverviewAnalytics::Reconciliation::Session.new(owner_id: this_user.id, type: metric_type.serialize)

    revisions_rel = model
      .where(repository_id: current_repository.id)

    revision_count = revisions_rel.count
    current_counts_by_state = revisions_rel
      .where(next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID)
      .group(:alert_resolved)
      .count
    current_count = current_counts_by_state.values.sum || 0
    current_open_count = current_counts_by_state[false] || 0
    current_closed_count = current_counts_by_state[true] || 0

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
end
