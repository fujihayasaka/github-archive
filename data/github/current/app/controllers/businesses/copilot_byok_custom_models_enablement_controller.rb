# typed: strict
# frozen_string_literal: true

class Businesses::CopilotByokCustomModelsEnablementController < Businesses::BusinessController
  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_copilot_enabled

  sig { void }
  def update
    if params[:enable_copilot_custom_models] == "enable"
      this_business.enable_copilot_custom_models(current_user)
    elsif params[:enable_copilot_custom_models] == "disable"
      this_business.disable_copilot_custom_models(current_user)
    end

    if params[:return_to]
      safe_redirect_to(params[:return_to])
    else
      redirect_to settings_copilot_enterprise_path(this_business)
    end
  end

  private

  sig { returns(Copilot::Business) }
  memoize def copilot_business
    Copilot::Business.new(this_business)
  end

  sig { void }
  def ensure_copilot_enabled
    render_404 unless copilot_business.copilot_enabled?
  end
end
