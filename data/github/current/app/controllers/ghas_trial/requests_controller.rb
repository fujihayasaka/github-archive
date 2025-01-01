# typed: true
# frozen_string_literal: true

class GhasTrial::RequestsController < ApplicationController
  before_action :dotcom_required
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:success]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :success], optional: true

  def index
    ghas_trial_request = Site::GhasTrialRequest.new(requester: current_user, organization: this_organization)
    return render_404 unless ghas_trial_request.can_send_request?

    render "ghas_trial/requests/index", locals: {
      ghas_trial_request: ghas_trial_request,
    }
  end

  def create
    ghas_trial_request = Site::GhasTrialRequest.new(ghas_trial_request_params)

    if ghas_trial_request.save
      redirect_to success_ghas_trial_requests_path
    else
      render "ghas_trial/requests/index", locals: { ghas_trial_request: ghas_trial_request }
    end
  end

  def success # rubocop:todo GitHub/UseRestfulActions
    render "ghas_trial/requests/success"
  end

  private

  memoize def this_organization
    Organization.find_by_login(params[:org])
  end

  def ghas_trial_request_params
    params
      .require(:site_ghas_trial_request)
      .permit(
        :name,
        :email,
        :country,
        :marketing_email_opt_in,
        :utm_campaign,
        :utm_medium,
        :utm_source,
        :utm_content
      ).merge(
        organization: this_organization,
        requester: current_user
      )
  end

  def target_for_conditional_access
    # cap_bypass:to_fix this controller is using Organizations
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ip_allowlist_enforceable
    :no
  end

  def external_conditional_access_policy_enforceable
    :no
  end

  def require_active_external_identity_session?
    false
  end

  def two_factor_enforceable
    :no
  end

  def emu_ownership_enforceable
    :no
  end
end
