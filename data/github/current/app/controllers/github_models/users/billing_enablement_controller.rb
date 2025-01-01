# typed: true
# frozen_string_literal: true

class GitHubModels::Users::BillingEnablementController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :require_feature
  before_action :github_models_required
  before_action :ensure_billing_enabled
  before_action :ensure_actor_can_change_billing

  def create
    respond_to do |format|
      format.turbo_stream do
        updated = if params[:enable_billing]
          current_user.enable_models_billing(current_user, instrument: false)
        else
          false
        end

        if updated
          redirect_to settings_models_path
        else
          head :unprocessable_entity
        end
      end
    end
  end

  def destroy
    respond_to do |format|
      format.turbo_stream do
        updated = if params[:disable_billing]
          current_user.disable_models_billing(current_user, instrument: false)
        else
          false
        end

        if updated
          redirect_to settings_models_path
        else
          head :unprocessable_entity
        end
      end
    end
  end

  private

  def ensure_actor_can_change_billing
    user = User.find_by_login(params[:user_id])
    render_404 if user != current_user
  end

  def require_feature
    unless user_feature_enabled?(:github_models_billing_ui)
      render_404
    end
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
