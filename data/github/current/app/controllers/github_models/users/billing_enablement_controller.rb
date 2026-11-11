# typed: true
# frozen_string_literal: true

class GitHubModels::Users::BillingEnablementController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :github_models_required
  before_action :ensure_billing_enabled
  before_action :ensure_actor_can_change_billing

  def create
    respond_to do |format|
      format.turbo_stream do
        if current_user.enable_models_billing(current_user)
          redirect_to settings_models_path
        else
          redirect_to settings_models_path, notice: "Something went wrong updating your Models billing settings. Please try again."
        end
      end
    end
  end

  def destroy
    respond_to do |format|
      format.turbo_stream do
        if current_user.disable_models_billing(current_user)
          redirect_to settings_models_path
        else
          redirect_to settings_models_path, notice: "Something went wrong updating your Models billing settings. Please try again."
        end
      end
    end
  end

  private

  def ensure_actor_can_change_billing
    user = User.find_by_login(params[:user_id])
    render_404 if user != current_user || user.is_enterprise_managed?
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
