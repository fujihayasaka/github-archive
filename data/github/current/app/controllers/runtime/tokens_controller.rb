# typed: true
# frozen_string_literal: true

module Runtime
  class TokensController < ApplicationController
    include ApplicationController::VerifiedFetchDependency

    before_action :require_logged_in_user
    before_action :require_feature_enabled

    allow_verified_fetch only: [:create]

    def create
      capi_token, capi_expiration = SparkRuntime::TokenService.encrypted_capi_token(user_session)

      if !FeatureFlag.vexi.enabled?(:spark_prompt_secret_scanning, current_user, default: false)
        return render json: { token: capi_token, expiration: capi_expiration }
      end

      scanning_token, scanning_token_expiration = SparkRuntime::TokenService.encrypted_secret_scanning_token(user_session)

      render json: { token: capi_token, expiration: capi_expiration, secret_scanning_token: scanning_token, secret_scanning_expiration: scanning_token_expiration }
    end

    private

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end

    def require_logged_in_user
      render_404 unless logged_in?
    end

    def require_feature_enabled
      access_denied unless current_user&.spark_enabled?
    end
  end
end
