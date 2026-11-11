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
  include Businesses::CopilotShared

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
      policies_path = if helpers.show_ai_controls?(this_business)
        copilot_enterprise_ai_controls_enterprise_path(this_business)
      else
        settings_copilot_enterprise_path(this_business)
      end
      render "businesses/enterprise_licensing/copilot/index", locals: {
        copilot_business: copilot_business,
        organizations: organizations,
        title: "Copilot",
        error: error,
        feature_requests: feature_requests_count_by_organizations,
        policies_path:,
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
      can_write: this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
    }
  end

  sig { returns(T.nilable(String)) }
  def get_tab
    return if !copilot_business.copilot_billable? && !copilot_business.has_trial_organization? && !this_business.digital_front_door?

    params[:tab] || nil
  end

  sig { void }
  def mark_request_a_feature_notifications_as_read
    async_mark_threads_as_read(MemberFeatureRequest::Notification.where(entity: this_business, user: current_user))
  end

end
