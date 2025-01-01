# typed: true
# frozen_string_literal: true

module GitAuth
  class Pipeline
    module Auth
      # Anything that RequestCredentials knows how to handle.
      class RequestCredentials < AuthenticationMethod
        class HTTPStatusNotOkError < StandardError; end
        MAX_RETRIES = 3

        def process
          creds = Api::RequestCredentials.new(login: input.member, password: input.password)
          creds.initialize_token_from_login_or_password

          auth_attempt = GitHub::Authentication::Attempt.new(
            allow_integrations:         true,
            allow_user_via_granular_actor: true,
            from:                       :git,
            login:                      creds.login, # rubocop:disable GitHub/DoNotAllowLogin this is a user inputted value for username/password and not display related
            password:                   creds.password,
            token:                      creds.token,
            ip:                         input.ip,
            request_id:                 input.request_id,
            repo:                       input.target_path,
            action:                     input.action,
            protocol:                   input.protocol,
          )

          if auth_attempt.result.failure_reason == :git_with_password_auth
            return result.fail_with :git_with_password_auth
          elsif auth_attempt.result.failure_reason == :weak_password
            return result.fail_with :weak_password
          elsif auth_attempt.result.failure_reason == :external_auth_token_required
            return result.fail_with :external_auth_token_required
          elsif auth_attempt.result.failure_reason == :ldap_timeout
            return result.fail_with :ldap_timeout
          elsif auth_attempt.result.suspended_integration_failure?
            return result.fail_with :suspended_integration
          elsif auth_attempt.result.suspended_failure?
            return result.fail_with :suspended
          end

          if auth_attempt.result.success?
            result.user = auth_attempt.result.user
            # Apparently token can be an empty string.
            if auth_attempt.token_present?
              result.token = auth_attempt.token
              token_type = auth_attempt.token_type(auth_attempt.token).to_s.gsub("_", "-")
              result.credential = "token:#{token_type}:#{hash_token(creds.token)}"
            else
              result.credential = "password"
            end
            result.success!
          end
        end

        private

        def applicable?
          !!input.password && GitHub::UTF8.valid_unicode3?(input.member)
        end
      end
    end
  end
end
