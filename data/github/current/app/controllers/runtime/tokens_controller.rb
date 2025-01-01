# typed: true
# frozen_string_literal: true

module Runtime
  class TokensController < ApplicationController
    include ApplicationController::VerifiedFetchDependency

    before_action :require_logged_in_user
    before_action :require_feature_enabled

    allow_verified_fetch only: [:create]

    def create
      raw_app_token, expires_at = SparkRuntime::AcaTokenService.mint_raw_app_token(user_session: user_session)
      encrypted_app_token = encrypt_token(raw_app_token)

      render json: { token: encrypted_app_token, expiration: expires_at }
    end

    private

    def encrypt_token(token)
      # using the CAPI encryption key is fully supported for this purpose, so use it instead of the spark key
      encrypted = GitHub.dotcom_capi_simple_box.encrypt(token)
      Base64.urlsafe_encode64(encrypted)
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end

    def require_logged_in_user
      render_404 unless logged_in?
    end

    def require_feature_enabled
      access_denied unless feature_enabled_globally_or_for_current_user?(:copilot_workbench)
    end
  end
end
