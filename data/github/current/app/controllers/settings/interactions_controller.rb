# typed: true
# frozen_string_literal: true

class Settings::InteractionsController < ApplicationController
  include Settings::ControllerMethods

  before_action :login_required
  before_action :ensure_user_abuse_mitigation_enabled

  ENABLED_MESSAGE = "Okay, we'll warn you when a blocked user is a prior contributor"
  DISABLED_MESSAGE = "You'll no longer be notified when a blocked user is a prior contributor"

  def update
    if interaction_setting.update(interaction_params)
      flash[:notice] = if interaction_setting.show_blocked_contributors_warning?
        ENABLED_MESSAGE
      else
        DISABLED_MESSAGE
      end
    else
      flash[:error] = interaction_setting.errors.full_messsages.to_sentence
    end

    redirect_to settings_blocked_users_path
  end

  private

  def ensure_user_abuse_mitigation_enabled
    return render_404 unless GitHub.user_abuse_mitigation_enabled?
  end

  def interaction_setting # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @interaction_setting ||= current_user.interaction_setting ||
      current_user.build_interaction_setting
  end

  def interaction_params
    params.require(:interaction_setting).permit(:show_blocked_contributors_warning)
  end
end
