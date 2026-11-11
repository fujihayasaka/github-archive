# typed: true
# frozen_string_literal: true

module ApplicationController::SocialLoginDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  # If a user is attempting to sign in through visual studio code using a social provider, redirect them to the social initiate path
  # Instead of assuming the user wants to use an existing account that is already signed in
  def vscode_social_initiate_redirect
    return if FeatureFlag.vexi.enabled?(:vscode_social_interstitial, current_user, default: false)
    return unless params[:provider].present?
    return if params[:skip_social_redirect] == "true"
    # Set a param to skip this redirect if the user has already been redirected once
    params[:skip_social_redirect] = "true"

    redirect_to social_initiate_path(provider: params[:provider], return_to: oauth_request_path(
      params.permit(
          :client_id,
          :redirect_uri,
          :response_type,
          :scope,
          :state,
          :code_challenge,
          :code_challenge_method,
          :allow_signup,
          :login,
          :prompt,
          :provider,
          :as_state,
          :skip_account_picker,
          :skip_social_redirect,
          :type,
          :get_started_with
        ).to_h.symbolize_keys
      )
    )
  end
end
