# typed: false
# frozen_string_literal: true

module GitHub
  module Authentication
    class OmniAuth < Default
      include UserHandler

      # Alias builtin web request authentication so we can override it for OmniAuth
      # but still call it if builtin authentication fallback is enabled.
      alias_method :builtin_rails_authenticate, :rails_authenticate

      # At this point an OmniAuth middleware has already authenticated the request,
      # so if the omniauth.auth env is present then the user is authenticated.
      #
      # Returns a User or nil and an optional message.
      def rails_authenticate(request, octolytics_id:, current_device_id:)
        omniauth_env = request.env["omniauth.auth"]
        GitHub::Authentication.logger.with_named_tags("code.namespace" => self.class.name, "code.function" => __method__, "http.client_ip" => request.remote_ip) do
          if omniauth_env && uid = omniauth_env["uid"]
            user, message = find_or_create_user(uid, user_info(omniauth_env))
            GitHub::Authentication.logger.with_named_tags("omniauth.uid" => uid) do
              if user && user.suspended?
                GitHub::Authentication.logger.info("omniauth failure - user suspended")
                GitHub::Authentication::Result.suspended_failure(
                  message: "User suspended",
                )
              elsif user
                GitHub::Authentication.logger.info("omniauth success")
                GitHub::Authentication::Result.success user
              else
                GitHub::Authentication.logger.info("omniauth failure - bad auth")
                GitHub::Authentication::Result.failure message: message
              end
            end
          elsif GitHub.auth.builtin_auth_fallback? && builtin_auth_attempt?(request) && !external_user?(request.params[:login])
            builtin_rails_authenticate(request, octolytics_id: octolytics_id, current_device_id: current_device_id)
          else
            GitHub::Authentication.logger.info("omniauth failure - user not found")
            GitHub::Authentication::Result.failure message: "Unknown User"
          end
        end
      end

      def external?
        true
      end

      def signup_enabled?
        false
      end

      def path(return_to = nil)
        self.class.path(return_to)
      end

      def self.path(return_to = nil)
        query_params = { return_to: return_to }
        "/auth/#{GitHub.auth_mode}?#{query_params.to_query}"
      end

      def add_middleware(builder)
        builder.use strategy, config
      end

      # Internal: pulls out any user attributes we've received from
      # the OmniAuth ENV. These are traditionally stored as "user_info"
      # but may differ depdnding on the strategy's implementation.
      #
      # omniauth_env  - The "omniauth.env" pulled from the request env.
      #
      # Returns a Hash.
      def user_info(omniauth_env)
        omniauth_env["user_info"]
      end
    end
  end
end
