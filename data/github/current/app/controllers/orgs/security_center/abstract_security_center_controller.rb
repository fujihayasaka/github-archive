# typed: true
# frozen_string_literal: true

require "github/security_center/logging_helper"

class Orgs::SecurityCenter::AbstractSecurityCenterController < Orgs::Controller
  abstract!

  extend T::Sig
  include GitHub::SecurityCenter::LoggingHelper

  # Telemetry
  before_action :instrument_security_center_page_visit, if: :instrument_security_center_page_visit?
  around_action :track_and_report_mysql_executions
  before_action :set_failbot_context
  around_action :set_log_context

  layout "security_center"
  javascript_bundle "security-center-filter-support"

  TEAM_DROPDOWN_THRESHOLD = 5000

  sig { returns(ActionController::Parameters) }
  memoize def params # rubocop:disable GitHub/UseRestfulActions
    T.let(super, ActionController::Parameters).deep_transform_keys!(&:underscore)
  end

  private

  sig { params(json: T.untyped, kwargs: T.untyped).void }
  def render_camelback_json(json:, **kwargs)
    render json: json.to_camelback_keys, **kwargs
  end

  def security_center_required
    render_404 unless ::SecurityCenter::SecurityFeatures.security_center_available?(this_organization)
  end

  sig { void }
  def ensure_query
    render json: { error: "Must provide a valid query" }, status: :bad_request unless params[:query]
  end

  def set_failbot_context
    Failbot.push(app: "github-security-center")
  end

  def set_log_context
    GitHub.logger.with_named_tags(
      "enduser.id": current_user&.display_login,
      "gh.enduser.id": current_user&.id,
      "gh.enduser.login": current_user&.display_login,
      "gh.org.id": this_organization.id,
      "gh.org.login": this_organization.display_login,
    ) do
      GitHub::MysqlInstrumenter.track! if this_organization.feature_enabled?(:security_center_undeclared_cluster_logging)
      yield
      log_undeclared_cluster_queries if this_organization.feature_enabled?(:security_center_undeclared_cluster_logging)
    end
  end

  def log_undeclared_cluster_queries
    controller_instance = env["action_controller.instance"]
    if controller_instance.present? && controller_instance.respond_to?(:required_clusters)
      required_cluster_names = Array(controller_instance.required_clusters).map(&:name)
      optional_cluster_names = Array(controller_instance.optional_clusters).map(&:name)

      GitHub::MysqlInstrumenter.queries.each do |query|
        if !required_cluster_names.include?(query.connection_class.to_s) &&
          !optional_cluster_names.include?(query.connection_class.to_s)
          GitHub.logger.warn(
            "Undeclared cluster query detected",
            "gh.security_center.db.query": query.sql,
            "gh.security_center.db.connection_class": query.connection_class,
            "gh.security_center.stacktrace": query.backtrace.join("\n"),
          )
        end
      end
    end
  end

  def ensure_security_overview_analytics_reconciliation
    SecurityOverviewAnalytics::ReconciliationScheduler.run_for(this_organization)
    SecurityOverviewAnalytics::FanoutScheduler.reconcile_for(this_organization)
  end

  def trigger_security_overview_analytics_backfill
    SecurityOverviewAnalytics::Initialization.for(this_organization).enqueue
    SecurityOverviewAnalytics::FanoutScheduler.initialize_for(this_organization)
  end

  def datadog_tags
    [
      "controller:#{GitHub::TaggingHelper.controller(env)}",
      "action:#{GitHub::TaggingHelper.action(env)}",
      "scope:organization"
    ]
  end

  sig { returns(T::Boolean) }
  def instrument_security_center_page_visit?
    self.class.method_defined?(:index) &&
    action_name == "index"
  end

  sig { void }
  def instrument_security_center_page_visit
    is_admin = this_organization.adminable_by?(current_user)
    can_manage_security_products = can_manage_security_products?
    user_role = if is_admin
      "org_owner"
    elsif can_manage_security_products
      "security_manager"
    else
      "org_member"
    end
    GitHub.dogstats.increment("security_center_page_visit", tags: datadog_tags + [
      "is_user_admin:#{is_admin}",
      "can_manage_security_products:#{can_manage_security_products}",
      "user_role:#{user_role}",
    ])
  end

  sig { params(event: String, event_payload: T.nilable(T::Hash[Symbol, T.untyped])).void }
  def instrument_audit_log_event(event:, event_payload: nil)
    payload = {
      scope: "org",
      org: this_organization.display_login,
      org_id: this_organization.id,
      user: current_user.display_login,
      user_id: current_user.id,
    }.merge(event_payload || {})

    GitHub.instrument(event, payload)
  end

  sig { returns(SecurityCenter::AuthorizationEnumerator) }
  memoize def auth_enumerator
    SecurityCenter::AuthorizationEnumerator.new(
      user: current_user,
      org: this_organization,
      datadog_tags:
    )
  end

  memoize def visible_features
    SecurityCenter::SecurityFeatures.visible_features(this_organization)
  end

  sig { returns(T::Boolean) }
  memoize def can_manage_security_products?
    SecurityProduct::Permissions::OrgAuthz.new(this_organization, actor: current_user).can_manage_security_products?
  end

  sig { returns([T.nilable(T::Array[Integer]), T::Boolean]) }
  memoize def adminable_repo_ids
    auth_enumerator.adminable_repo_ids
  end

  sig { returns(T::Hash[String, [T::Array[Integer], T::Boolean]]) }
  memoize def allowed_repository_ids_by_feature_for_organization_members
    auth_enumerator.allowed_repository_ids_by_feature_for_organization_member
  end

  instrument_method \
    :can_manage_security_products?,
    :adminable_repo_ids,
    :allowed_repository_ids_by_feature_for_organization_members,
    :render_camelback_json,
    :visible_features
end
