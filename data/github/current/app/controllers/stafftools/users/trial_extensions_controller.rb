# typed: true
# frozen_string_literal: true

class Stafftools::Users::TrialExtensionsController < StafftoolsController
  include MarketingMethods

  before_action :ensure_user_exists

  def create
    plan_trial = ::Billing::EnterpriseCloudTrial.new(this_user)
    success = plan_trial.extend_trial(extension_length)

    if success
      flash[:notice] = "Trial was successfully extended"
    else
      flash[:error] = "Unable to extend trial"
    end

    analytics_event(
      **organization_trial_extension_ga_event_attributes(
        success,
        this_user,
        current_user
      )
    )

    redirect_to :back
  end

  private

  def extension_length
    params[:extension_length].to_i.days
  end
end
