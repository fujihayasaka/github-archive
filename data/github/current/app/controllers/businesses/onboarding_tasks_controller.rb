# typed: true
# frozen_string_literal: true

class Businesses::OnboardingTasksController < Businesses::BusinessController
  before_action :login_required
  before_action :dotcom_required
  before_action :eligible_business_required
  before_action :allowed_notice_required
  before_action do
    T.bind(self, Businesses::OnboardingTasksController)
    business_access_required(allow_members: true)
  end

  def update
    current_user.reset_business_notice(notice_name, business_id: this_business.id)
    redirect_to enterprise_getting_started_path(this_business)
  end

  private

  def eligible_business_required
    return if this_business.seats_plan_basic?
    return if this_business.trial?
    return if show_org_upgrade_onboarding_experience?(this_business)

    render_404
  end

  def allowed_notice_required
    render_404 unless allowed_notices.include?(notice_name)
  end

  def notice_name
    params[:notice_name].to_s
  end

  def allowed_notices
    [
      BusinessesHelper::TRIAL_ONBOARDING_NOTICE_NAME,
      BusinessesHelper::COPILOT_ONBOARDING_NOTICE_NAME,
    ]
  end
end
