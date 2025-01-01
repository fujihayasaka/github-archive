# typed: true
# frozen_string_literal: true

require "github/security_center/logging_helper"

class Businesses::SecurityCenter::AbstractSecurityCenterController < Businesses::BusinessController
  abstract!
  include GitHub::SecurityCenter::LoggingHelper

  layout "layouts/react_business"

  # Access
  before_action :login_required
  before_action do
    T.bind(self, Businesses::SecurityCenter::AbstractSecurityCenterController)
    business_access_required(allow_members: true)
  end
  before_action do
    T.bind(self, Businesses::SecurityCenter::AbstractSecurityCenterController)
    redirect_billing_manager_and_viewer_to_billing_settings(skip_redirecting_members: true)
  end

  # Telemetry
  before_action :instrument_page_visit, if: :instrument_page_visit?
  around_action :track_and_report_mysql_executions
  before_action :set_failbot_context
  around_action :set_log_context

  sig { returns(ActionController::Parameters) }
  memoize def params # rubocop:disable GitHub/UseRestfulActions
    T.let(super, ActionController::Parameters).deep_transform_keys!(&:underscore)
  end

  private

  def show_blankslate
    authorized_orgs.empty? && !can_see_personal_repos?
  end

  def blankslate_description
    description = "Organization repositories are only shown for organizations where you
    have permissions to fully manage code security."

    if ::SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(this_business)
      description += " User namespace repositories are only
        shown if you have permissions to fully manage code security across the enterprise."
    end

    description
  end

  def set_failbot_context
    Failbot.push(app: "github-security-center")
  end

  def set_log_context
    GitHub.logger.with_named_tags(
      "enduser.id": current_user.display_login,
      "gh.enduser.id": current_user.id,
      "gh.enduser.login": current_user.display_login,
      "gh.business.id": this_business.id,
      "gh.business.name": this_business.name,
    ) do
      yield
    end
  end

  def deep_camelize_keys(obj)
    case obj
    when Hash
      obj.each_with_object({}) do |(k, v), result|
        new_key =
          if k.is_a?(Symbol)
            k.to_s.camelize(:lower)
          elsif k.is_a?(String) && k =~ /\A[a-z]+(_[a-z]+)+\z/
            k.camelize(:lower)
          else
            k
          end
        result[new_key] = deep_camelize_keys(v)
      end
    when Array
      obj.map { |v| deep_camelize_keys(v) }
    else
      obj
    end
  end

  sig { params(json: T.untyped, kwargs: T.untyped).void }
  def render_camelback_json(json:, **kwargs)
    render json: deep_camelize_keys(json), **kwargs
  end

  sig { returns(::SecurityProduct::Permissions::BusinessAuthzEnumerator) }
  memoize def authz_enumerator
    ::SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
      actor: current_user,
      business: this_business,
      actions: authorized_orgs_actions,
      cap_filter:,
    )
  end

  sig { abstract.returns(T.nilable(T.any(Symbol, T::Array[Symbol]))) }
  def authorized_orgs_actions; end

  # If #authorized_orgs_actions returns a value,
  #   Returns the union of the authorized organizations for all actions specified by #authorized_orgs_actions.
  #   For example, if #authorized_orgs_by_action returns { action1: [org1], action2: [org2] }, then this method returns [org1, org2].
  # If #authorized_orgs_actions returns nil,
  #   Returns the authorized organizations where the current user has membership.
  sig { returns(T::Array[Organization]) }
  def authorized_orgs
    if authorized_orgs_actions.nil?
      authz_enumerator.authorized_orgs_where_actor_has_membership
    else
      authz_enumerator.authorized_orgs_by_action.values.flatten.uniq
    end
  end

  sig { returns(T::Hash[Symbol, T::Array[::Organization]]) }
  def authorized_orgs_by_action
    authz_enumerator.authorized_orgs_by_action
  end

  sig { returns(T::Array[Organization]) }
  def unauthorized_orgs
    if authorized_orgs_actions.nil?
      authz_enumerator.unauthorized_orgs_where_actor_has_membership
    else
      authz_enumerator.unauthorized_orgs_for_actions
    end
  end

  def sso_payload
    # Payload we pass in to the react partial for the new SSO banner
    {
      base_avatar_url: GitHub.alambic_avatar_url,
      sso_organizations: unauthorized_orgs.map { |org| { id: org.id.to_s, name: org.name, login: org.display_login } }
    }
  end

  sig { params(feature_flags: T.nilable(T::Hash[Symbol, T::Boolean])).returns(T.proc.void) }
  def content_app_payload_generator(feature_flags: nil)
    -> do
      {
        variant: "content",
        sso_organizations: sso_payload[:sso_organizations],
        enabled_features: feature_flags,
      }
    end
  end

  sig do
    params(
      heading: String,
      message: String,
      subheading: T.nilable(String),
      description: T.nilable(String),
      learn_more_link: T.nilable({ text: String, url: String }),
      release_phase: Symbol
    ).returns(T.proc.void)
  end
  def blankslate_app_payload_generator(heading:, message:, subheading: nil, description: nil, learn_more_link: nil, release_phase: :ga)
    feedback = ::SecurityCenter::FeedbackLink.new(
      phase: release_phase,
      actor: T.must(current_user),
      scope: this_business,
    )

    -> do
      {
        variant: "blankslate",
        sso_organizations: sso_payload[:sso_organizations],
        heading:,
        subheading:,
        message:,
        description:,
        learn_more_link:,
        feedback_link: {
          text: feedback.text,
          url: feedback.url,
        },
      }.deep_transform_keys { |key| key.to_s.camelize(:lower) }
    end
  end

  def security_center_required
    render_404 unless SecurityCenter::SecurityFeatures.security_center_available?(this_business)
  end

  memoize def visible_features
    SecurityCenter::SecurityFeatures.visible_features(this_business)
  end

  sig { returns(T::Boolean) }
  def instrument_page_visit?
    return false unless this_business.present?
    return false unless logged_in?

    self.class.method_defined?(:index) &&
    action_name == "index"
  end

  sig { void }
  def instrument_page_visit
    GitHub.dogstats.increment("security_center_page_visit", tags: [
      "controller:#{GitHub::TaggingHelper.controller(env)}",
      "action:#{GitHub::TaggingHelper.action(env)}",
      "scope:business",
      "is_user_business_owner:#{this_business.owner?(current_user)}",
    ])
  end

  sig { params(event: String, event_payload: T.nilable(T::Hash[Symbol, T.untyped])).void }
  def instrument_audit_log_event(event:, event_payload: nil)
    payload = {
      scope: "business",
      business: this_business,
      actor: current_user,
    }.merge(event_payload || {})

    GitHub.instrument(event, payload)
  end

  def ensure_security_center_reconciliation
    this_business.trigger_security_center_reconciliation
  end

  def ensure_security_overview_analytics_reconciliation
    SecurityOverviewAnalytics::ReconciliationScheduler.run_for(this_business)
    SecurityOverviewAnalytics::FanoutScheduler.reconcile_for(this_business)
  rescue => e # rubocop:disable Lint/RescueException
    # Does not block controller action if fails to attempt the reconciliation
    Failbot.report!(e)
  end

  def trigger_security_overview_analytics_backfill
    SecurityOverviewAnalytics::Initialization.for(this_business).enqueue
    SecurityOverviewAnalytics::FanoutScheduler.initialize_for(this_business)
  rescue => e # rubocop:disable Lint/RescueException
    # Does not block controller action if fails to attempt the backfill
    Failbot.report!(e)
  end

  sig { returns(T::Boolean) }
  def can_see_personal_repos?
    # This is not a feature flag check, but it is routed through FeatureFlagHelper
    return false unless ::SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(this_business)
    SecurityProduct::Permissions::BusinessAuthz.new(this_business, actor: current_user).can_view_user_owned_repository_alerts?
  end

  instrument_method \
    :authorized_orgs,
    :authorized_orgs_by_action,
    :unauthorized_orgs,
    :render_camelback_json,
    :can_see_personal_repos?
end
