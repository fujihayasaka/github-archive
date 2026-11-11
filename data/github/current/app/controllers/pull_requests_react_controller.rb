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

  allow_verified_fetch only: [:toggle_generic_feature]

  layout "layouts/repository_with_container"

  stylesheet_bundle :"pull-requests"
  stylesheet_bundle "copilot-code-review"

  # Consider using feature_preview_controller#toggle instead
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
