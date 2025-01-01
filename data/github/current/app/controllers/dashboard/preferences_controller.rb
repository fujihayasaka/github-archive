# typed: true
# frozen_string_literal: true

class Dashboard::PreferencesController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required

  allow_verified_fetch only: [:update]

  sig { void }
  def update
    write_to_user_settings

    head :no_content
  end

  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def user_settings_params
    params.permit(
      :new_user_has_customized_account,
      :new_user_has_tried_copilot,
      :new_user_has_created_repo,
      :nux_dashboard_playlist_dismissed,
      :nux_dashboard_getting_started_dismissed,
      :nux_dashboard_docs_dismissed,
      :nux_dashboard_recommendations_dismissed,
      :nux_dashboard_vscode_dismissed,
      :nux_dashboard_desktop_dismissed,
      :productivity_dashboard_selected_tab,
    )
  end

  def write_to_user_settings
    user_settings_params.each do |param_key, value|
      current_user.settings.set!(param_key, value)
    end
  end
end
