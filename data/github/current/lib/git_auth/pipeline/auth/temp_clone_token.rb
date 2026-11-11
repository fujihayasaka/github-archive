# typed: true
# frozen_string_literal: true

module GitAuth
  class Pipeline
    module Auth
      class TempCloneToken < AuthenticationMethod
        def applicable?
          GitHub::Authentication::SignedAuthToken.valid_format?(input.password)
        end

        def process
          signed_auth_token = verify_temp_clone_token(input.password, input.repository)

          # This isn't a Temp clone token, return inconclusive to process like a password
          return if !signed_auth_token.valid? && [:user_suspended, :expired].exclude?(signed_auth_token.reason)

          # Temp clone tokens can't be used for writes, so fail here first
          return result.fail_with :no_writes_with_clone_token if input.action == :write

          # Temp clone tokens can't be used for wikis or gists
          if input.target_path.end_with?(".wiki.git") || input.repository.is_a?(Gist)
            return result.fail_with :auth_error
          end

          # The token was invalid for a reason other than bad login
          if !signed_auth_token.valid?
            return result.fail_with :temp_clone_token_expired if signed_auth_token.reason == :expired
            return result.fail_with :auth_error
          end

          result.user = signed_auth_token.user
          result.credential = "token:temp-clone:#{hash_token(input.password)}"
          result.success!
        end

        private

        def verify_temp_clone_token(token, repository)
          User.verify_signed_auth_token(
            token: token,
            # The scope is hard-coded here and in the Repository model,
            # where the temp clone tokens are generated.
            scope: "TemporaryCloneURL:#{repository&.id.to_i}:read",
          )
        end
      end
    end
  end
end
