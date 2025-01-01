# typed: true
# frozen_string_literal: true

module Runtime
  class AuthController < ApplicationController

    ALLOWED_DOMAIN_SUFFIXES = %w[
      github.app
      mitalicustomdomain.net
    ]

    PUBLIC_KEYS = [
      {
        "kty": "EC",
        "kid": "c1302e95-a2f1-4bd3-9d48-dfa19089f1f3",
        "crv": "P-384",
        "x": "gjS9QOFW1N-714Ak4JTNMGEfRQ9PIbacptnJjq1TyZ5cdGyQ2Y4GR-toQsMnc-D_",
        "y": "s1MHCJGI3nXbwth-HTnJW7FlGg47G1m5bDw-nyEm9oBgkOtIuqv7t1qq3lQzPpWr"
      },
    ]

    depends_on_clusters ApplicationRecord::Collab,
      ApplicationRecord::Copilot,
      ApplicationRecord::Iam,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Permissions

    before_action :require_logged_in_user, except: [:jwks]
    before_action :require_feature_enabled, except: [:jwks]

    javascript_bundle :runtime


    def authenticate # rubocop:disable GitHub/UseRestfulActions
      return render_404 unless params[:user] && params[:app] && params[:pb]

      user = params[:user]
      app = params[:app]
      postback_uri = params[:pb]

      allowed = SparkRuntime::AccessChecker.new(app, current_user).allowed?

      # TODO: Check whether the given user is allowed to use the app via permissions eventually
      return render_404 unless allowed || postback_uri.ends_with?("mitalicustomdomain.net")

      # TODO: Validate that the postback URL is a known deployment
      return render_404 unless valid_postback?(postback_uri)

      encrypted_app_token = SparkRuntime::AcaTokenService.mint_encrypted_jwt(app_name: app, app_owner_login: user, user_session: user_session)
      at_hash = SparkRuntime::AcaTokenService.token_at_hash(encrypted_app_token)

      aca_jwt = SparkRuntime::AcaJwtGenerator.new(
        app,
        user,
        GitHub.copilot_workbench_aca_jwt_private_key,
        at_hash).jwt

      render "runtime/aca", locals: {
        app:,
        postback_uri:,
        user:,
        payload: aca_jwt,
        proxyPayload: encrypted_app_token,
      }
    end

    def jwks # rubocop:disable GitHub/UseRestfulActions
      # Be nice and spit it out in HTML as well
      respond_to do |format|
        format.html do
          render json: { keys: PUBLIC_KEYS }
        end

        format.json do
          render json: { keys: PUBLIC_KEYS }
        end
      end
    end

    private

    def valid_postback?(postback_uri)
      parsed = URI.parse(postback_uri)
      ALLOWED_DOMAIN_SUFFIXES.any? do |suffix|
        parsed.host&.end_with?(".#{suffix}")
      end
    end

    def require_logged_in_user
      access_denied unless logged_in?
    end

    def require_feature_enabled
      access_denied unless feature_enabled_globally_or_for_current_user?(:copilot_workbench)
    end

    def resource_for_conditional_access
      return current_user if logged_in?
      :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    end

    def target_for_conditional_access
      return current_user if logged_in?
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end
end
