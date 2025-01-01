# typed: true
# frozen_string_literal: true

module Runtime
  class AuthController < ApplicationController

    ALLOWED_DOMAIN_SUFFIXES = %w[
      github.app
      mitalicustomdomain.net
      users.github.app
      beta.github.app
      users.beta.github.app
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

      # A request to this controller method will take the following forms:
      # https://github.com/spark/runtime/auth?user=fce17ac5f2df384024a8&app=7770047f97a49fae8331&pb=https%3A%2F%2Fhello-world-app--justinmcbride.github.app
      # The user parameter contains the spark owner's deploy_login or the spark owner's permanent_name, depending on API version.
      # The app parameter will always contain the app's permanent_name.
      # The postback_uri will contain the friendly name for both the user and the app
      # Some valid postback_uri (pb) examples are:
      # https%3A%2F%2Fhello-world-app--justinmcbride.github.app
      # https%3A%2F%2Fhello-world-app--justinmcbride.beta.github.app
      # https%3A%2F%2Fhello-world-app--jumcbride-microsoft.users.github.app
      # The postback_uri can also contain a revision of the app, such as the spark-preview:
      # https%3A%2F%2Fspark-preview--hello-world-app--justinmcbride.github.app

      allowed = SparkRuntime::AccessChecker.from_app_name(app, current_user).allowed?

      # TODO: Check whether the given user is allowed to use the app via permissions eventually
      return render_404 unless allowed || postback_uri.ends_with?("mitalicustomdomain.net")

      # Validate that the parameters match the postback URI
      return render_404 unless valid_postback?(user, app, postback_uri)

      encrypted_app_token, token_expires_at = SparkRuntime::TokenService.encrypted_aca_jwt(user_session: user_session, app_name: app, app_owner_login: user)
      at_hash = SparkRuntime::TokenService.token_at_hash(encrypted_app_token)

      aca_jwt = SparkRuntime::AcaJwtGenerator.new(
        app,
        user,
        GitHub.copilot_workbench_aca_jwt_private_key,
        at_hash,
        token_expires_at).jwt

      should_forward_region = FeatureFlag.vexi.enabled?(:spark_aca_regions, current_user, default: false)
      if should_forward_region
        region = params["x-ms-region"]
      else
        region = nil
      end

      read_only_kv_enabled = FeatureFlag.vexi.enabled?(:spark_read_only_kv, current_user, default: false)
      if read_only_kv_enabled
        runtime_app = Spark::RuntimeApp.find_by(permanent_name: app)
        read_only_kv = runtime_app&.read_only_kv || false
        if read_only_kv && current_user.id != runtime_app.user_id
          return render "runtime/read_only_confirmation", locals: {
            app:,
            postback_uri:,
            user:,
            payload: aca_jwt,
            proxyPayload: encrypted_app_token,
            region:,
          }
        end
      end

      render "runtime/aca", locals: {
        app:,
        postback_uri:,
        user:,
        payload: aca_jwt,
        proxyPayload: encrypted_app_token,
        region:,
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

    def parse_postback_uri(postback_uri)
      return nil unless postback_uri

      begin
        parsed = URI.parse(postback_uri)
        full_host = parsed.host
        return nil unless full_host

        # For standard domains, parse the subdomain structure
        # Expected formats:
        # - app-name--username.github.app
        # - app-name--username.users.github.app
        # - app-name--username.beta.github.app
        # - revision--app-name--username.github.app
        subdomain, host = full_host.split(".", 2)
        return nil unless subdomain
        return nil unless host

        # Split on double dashes to get components
        components = subdomain.split("--")
        return nil if components.empty?

        case components.length
        when 2
          # Format: app-name--username
          {
            app_name: components[0],
            username: components[1],
            revision: nil,
            domain: host,
          }
        when 3
          # Format: revision--app-name--username
          {
            app_name: components[1],
            username: components[2],
            revision: components[0],
            domain: host,
          }
        else
          # Unexpected format
          {
            domain: host,
          }
        end
      rescue URI::InvalidURIError
        nil
      end
    end

    def valid_postback?(user_param, app_param, postback_uri)
      # Parse the postback URI to extract components
      parsed_postback = parse_postback_uri(postback_uri)
      return false unless parsed_postback

      # Skip validation for mitalicustomdomain.net domains as they have special handling
      return true if parsed_postback[:domain].ends_with?(".mitalicustomdomain.net") || parsed_postback[:domain] == "mitalicustomdomain.net"

      # Validate that we were able to parse the postback URI (mitalicustom doesn't need these checks)
      return false unless parsed_postback[:app_name] && parsed_postback[:username]

      return false unless ALLOWED_DOMAIN_SUFFIXES.include?(parsed_postback[:domain])

      # Look up the runtime app by permanent_name (app_name from postback)
      # Note: theoretically, the permanent_name of a spark should unique across ALL users, due to DB constraints
      # that we have on the Spark::RuntimeApp model. So we can find the specific app by its permanent_name, without
      # taking into account the user.
      runtime_app = Spark::RuntimeApp.find_by(permanent_name: app_param)
      return false unless runtime_app

      owner = runtime_app.runtime_app_owner
      if SparkRuntime::OwnerApiKV.is_new_api_version?(owner.permanent_name)
        # For 1.1 users, the user param will be the user permanent_name, while the postback will contain the deploy_login
        return false unless owner.deploy_login.casecmp?(parsed_postback[:username])
        return false unless owner.permanent_name == user_param

        # We also care about the postback domain
        # TODO: Add beta subdomain support: https://github.com/github/spark/issues/1417
        if owner.is_segregated?
          return false unless parsed_postback[:domain] == "users.github.app"
        else
          return false unless parsed_postback[:domain] == "github.app"
        end
      else
        # For 1.0 users, the user param should be the deploy_login of the owner
        return false unless user_param.casecmp?(owner.deploy_login)
        return false unless user_param.casecmp?(parsed_postback[:username])
      end

      return false unless parsed_postback[:app_name] == runtime_app.permanent_name || parsed_postback[:app_name] == runtime_app.friendly_name

      # Only the app owner is allowed to view the spark-preview special revision
      if parsed_postback[:revision] == "spark-preview"
        return false unless runtime_app.runtime_app_owner.owner == current_user
      end

      true
    end

    def require_logged_in_user
      access_denied unless logged_in?
    end

    def require_feature_enabled
      access_denied unless current_user&.spark_enabled? || FeatureFlag.vexi.enabled?(:copilot_workbench_access_deployed_sparks, current_user, default: false)
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
