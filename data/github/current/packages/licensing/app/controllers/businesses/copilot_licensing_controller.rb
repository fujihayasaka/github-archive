# typed: strict
# frozen_string_literal: true

class Businesses::CopilotLicensingController < Businesses::BusinessController

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :check_business_is_not_trial_without_cfb_authorization
  before_action :mark_request_a_feature_notifications_as_read, only: [:index]
  before_action :ensure_enterprise_copilot_licensing_enabled

  javascript_bundle :copilot

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ApplicationHelper
  include GitHub::Memoizer

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  PER_PAGE = 10

  sig { void }
  def index
    render_index(organizations: paginated_orgs)
  end

  private

  sig { returns(Copilot::Business) }
  def copilot_business # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @copilot_business ||= T.let(Copilot::Business.new(this_business), T.nilable(Copilot::Business))
  end

  sig { void }
  def check_business_is_not_trial_without_cfb_authorization
    render_404 if this_business.trial? && !this_business.digital_front_door?
  end

  sig { params(organizations: T::Array[::Organization], error: T.nilable(String)).void }
  def render_index(organizations:, error: nil)
    Copilot::Instrumenter.instrument_clickwrap_shown(current_user, this_business)

    if Copilot::Business.new(this_business).eligible_for_first_run_flow?
      render "businesses/copilot_settings/first_run_flow_cta"
      return
    end

    if standalone_business?
      render_standalone_index(error: error)
    else
      render "businesses/enterprise_licensing/copilot/index", locals: {
        copilot_business: copilot_business,
        organizations: organizations,
        title: "Copilot",
        error: error,
        feature_requests: feature_requests_count_by_organizations,
      }
    end
  end

  sig { params(error: T.nilable(String)).void }
  def render_standalone_index(error: nil)
    render "businesses/copilot_settings/standalone_index", locals: {
      copilot_business: copilot_business,
      title: "Copilot Business",
      error: error,
      features_for_data_retention: get_features_for_data_retention,
      tab: get_tab || "policies",
    }
  end

  sig { returns(T::Array[::Organization]) }
  def paginated_orgs
    page = params[:page] || 1

    if feature_requests_from_admins.any? || feature_requests_from_members_of_organizations.any?
      MemberFeatureRequest.sorted_organizations_by_features(
        organizations: this_business.organizations,
        admin_feature_requests: feature_requests_from_admins,
        member_feature_requests: feature_requests_from_members_of_organizations
      ).paginate(page: page, per_page: PER_PAGE).to_a
    else
      this_business.organizations.paginate(page: page, per_page: PER_PAGE).to_a
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def feature_requests_count_by_organizations
    MemberFeatureRequest.feature_requests_count_by_organizations(
      admin_feature_requests: feature_requests_from_admins,
      member_feature_requests: feature_requests_from_members_of_organizations
    )
  end

  sig { returns(ActiveRecord::Relation) }
  memoize def feature_requests_from_admins
    MemberFeatureRequest.active_request_entities.where(billing_entity: this_business).includes(:request_entity, :requester)
  end

  sig { returns(ActiveRecord::Relation) }
  memoize def feature_requests_from_members_of_organizations
    MemberFeatureRequest.active_request_entities.where(billing_entity: this_business.organizations.pluck(:id)).includes(:request_entity, :requester)
  end

  sig { returns(T::Array[::Organization]) }
  def orgs_matching_query
    page = params[:page] || 1
    query = params[:query]
    this_business.organizations.where("`login` like ?", "%#{query}%").paginate(page: page, per_page: PER_PAGE).to_a
  end

  sig { returns(T.nilable(String)) }
  def get_tab
    return if !copilot_business.copilot_billable? && !copilot_business.has_trial_organization? && !this_business.digital_front_door?

    params[:tab] || nil
  end

  sig { returns(T::Boolean) }
  def standalone_business?
    copilot_business.copilot_standalone?
  end

  sig { void }
  def mark_request_a_feature_notifications_as_read
    async_mark_threads_as_read(MemberFeatureRequest::Notification.where(entity: this_business, user: current_user))
  end

  sig { returns(String) }
  def get_features_for_data_retention
    return "" unless copilot_business.copilot_plan_business?

    features = []
    features << Copilot::CLI_UI_NAME
    features << Copilot::COPILOT_IN_DOTCOM if copilot_business.has_copilot_enterprise_access? && !standalone_business?
    features << Copilot::COPILOT_CHAT_IN_MOBILE
    features << Copilot::COPILOT_SWE_AGENT if (!GitHub.multi_tenant_enterprise? || FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, this_business, default: false)) && !standalone_business?
    return "Enabling #{features.to_sentence} will collect additional data" if !features.empty?
    ""
  end
end
