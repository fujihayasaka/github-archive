# typed: true
# frozen_string_literal: true

class Site::Enterprise::TrialsController < Site::Enterprise::BaseController
  depends_on_clusters ApplicationRecord::Mysql1, only: [:start, :callback]

  depends_on_clusters ApplicationRecord::Collab, only: [:start, :callback]

  def start # rubocop:todo GitHub/UseRestfulActions
    if logged_in?
      redirect_to new_organization_path(plan: GitHub::Plan.business_plus, trial_acquisition_channel: "resources")
    else
      redirect_to signup_path(plan: GitHub::Plan.business_plus, setup_organization: true, trial_acquisition_channel: "resources")
    end
  end

  def callback # rubocop:todo GitHub/UseRestfulActions
    redirect_to home_path and return if !logged_in?
    redirect_to home_path and return if cookies[:enterprise_trial_redirect_to].blank?

    organization = Organization.find_by(login: cookies[:enterprise_trial_redirect_to])

    redirect_to home_path and return if organization.blank?

    redirect_to user_path(organization)
  end
end
