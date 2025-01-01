# typed: true
# frozen_string_literal: true

class PullRequestsReactController < AbstractRepositoryController
  include GitHub::Memoizer
  include CopilotAuthHelper

  before_action :login_required

  include BranchesHelper
  include RelayHelper
  include InternalGraphqlTracingHelper
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:toggle_new_mergebox, :toggle_generic_feature]

  layout "layouts/repository_with_container"

  stylesheet_bundle :"pull-requests"

  preload_features [:mergebox_react_partial], only: [:toggle_new_mergebox]

  def toggle_new_mergebox # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless logged_in? && request&.method == "POST" && user_feature_enabled?(:mergebox_react_partial)
    pull_number = params[:pull_number]
    new_state = params[:new_state]
    redirect_path = if pull_number
      show_pull_request_path(current_repository.owner_display_login, current_repository.name, pull_number)
    else
      :back
    end

    if !current_user&.feature_preview_enabled?(:mergebox_react_partial, enrolled_by_default_override: user_feature_enabled?(:new_merge_experience_opt_out_by_default))
      current_user&.enable_feature_preview(:mergebox_react_partial) unless new_state == "disabled"
      if request&.xhr?
        head :ok
      else
        redirect_to redirect_path.to_s + "?new_mergebox=true"
      end
    else
      current_user&.disable_feature_preview(:mergebox_react_partial) unless new_state == "enabled"
      if request&.xhr?
        head :ok
      else
        redirect_to redirect_path.to_s + "?new_mergebox=false"
      end
    end
  end

  def toggle_generic_feature # rubocop:todo GitHub/UseRestfulActions
    feature_name = params[:feature_name]

    return render_404 unless logged_in?
    return render_404 unless user_feature_enabled?(feature_name)

    if current_user&.feature_preview_enabled?(feature_name)
      current_user&.disable_feature_preview(feature_name)
      enabled = false
    else
      current_user&.enable_feature_preview(feature_name)
      enabled = true
    end

    if request&.xhr?
      head :ok
    else
      friendly_feature_name = friendly_feature_name_map[feature_name]

      redirect_uri = Addressable::URI.parse(request.referrer)

      redirect_uri.query_values = {
        friendly_feature_name => enabled,
      } if friendly_feature_name

      safe_redirect_to(redirect_uri.to_s, fallback: :back)
    end
  end

  private

  # map feature names to more user-friendly names for use in query params
  def friendly_feature_name_map
    {
      "prx_files" => "new_files_changed",
    }
  end
end
