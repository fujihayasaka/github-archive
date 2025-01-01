# typed: true
# frozen_string_literal: true

module GitAuth
  class Pipeline
    module Auth
      # A gitauth signed token (as opposed to a github signed token).
      # Currently only full trust tokens are implemented.
      class SignedToken < AuthenticationMethod
        def applicable?
          GitHub::Authentication::GitAuth::SignedAuthToken.valid_format?(input.password)
        end

        def process
          auth = GitHub::Authentication::GitAuth::SignedAuthToken.verify(
            token: input.password,
            scope: input.action.to_s,
          )
          unless auth.valid?
            return result.fail_with :invalid_full_trust_token
          end
          if auth.data.empty?
            return result.fail_with :invalid_full_trust_token
          end
          if auth.repo != input.repository
            return result.fail_with :invalid_full_trust_token
          end
          # We don't currently support these tokens for SSH-based operations.
          # If we start using full trust tokens to access Gists, then
          # we should consider whether we need to account for the use
          # case where gists cannot be accessed via the 'git' protocol.
          if auth.data["proto"] != "http"
            return result.fail_with :invalid_full_trust_protocol
          end

          # Currently only full trust tokens are implemented.
          unless auth.data["member"].start_with?("gitauth-full-trust:")
            raise ArgumentError, "gitauth token minted for unknown user or service"
          end

          result.member = auth.data["member"]
          # This should change if we get things other than full-trust tokens.
          result.credential = "token:#{result.member}:#{hash_token(input.password)}"
          result.success!
        end
      end
    end
  end
end
