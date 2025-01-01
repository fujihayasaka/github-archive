# typed: true
# frozen_string_literal: true

module ProgrammaticAccessToken
  class BulkDestroy
    VERIFIER_BATCH_SIZE = 100
    REVOKE_BATCH_SIZE = 20

    VALID_DESTROY_REASONS = {
      revocation_api: "deleted by the credential revocation API",
    }

    STATS_KEY = "programmatic_access_token.bulk_destroy"

    def self.perform(tokens, opts = {})
      new(tokens, opts).perform
    end

    def initialize(tokens, opts)
      @tokens = tokens
      @opts = opts
    end

    def perform
      GitHub.dogstats.increment(STATS_KEY, tags: ["state:start"])

      if destroy_reason.nil?
        GitHub.dogstats.increment(STATS_KEY, tags: ["state:destroy_reason", "result:failure", "reason:invalid_destroy_reason"])
        return Result.failed("Invalid destroy reason")
      end

      # {credential_id => access_id}
      # In order to not iterate through the entire verify response again,
      # we are storing the access_id in a hash with the credential_id as the key
      verified_credential_ids = {}

      # For any successful revokes, we are grabbing the access_ids from the verified_credential_ids hash
      # and returning them in the response
      access_ids = T.let([], T::Array[Integer])

      # For any tokens that we failed to verify because of an error
      # We still need to see if they are valid, so we will just return them in the response
      unverified_tokens = T.let([], T::Array[String])

      @tokens.each_slice(VERIFIER_BATCH_SIZE) do |tokens_batch|
        verify_credentials_response = verify_credentials(tokens_batch)
        unless verify_credentials_response.success?
          # We should not stop the entire process if we have verification errors
          # There may be more tokens to verify, we should at least log it for now
          GitHub.dogstats.increment(STATS_KEY, tags: ["state:verification_batch", "result:failure", "reason:authnd_verification_error"])
          GitHub.logger.error("Failed to verify some credentials for bulk destroy", {
            "code.namespace" => "programmatic_access_token.bulk_destroy",
            "code.function" => "perform",
            "errors" => verify_credentials_response.error,
          })
          unverified_tokens.concat(tokens_batch)
          next
        end
        verify_credentials_response.value.each do |credential|
          if credential.is_verified
            verified_credential_ids[credential.credential_id] = credential.access_id
            GitHub.dogstats.increment(STATS_KEY, tags: ["state:single_verification_check", "result:success"])
          else
            GitHub.dogstats.increment(STATS_KEY, tags: ["state:single_verification_check", "result:failure", "reason:#{credential.result}"])
          end
        end
      end

      return Result.success if verified_credential_ids.empty? && unverified_tokens.empty?

      verified_credential_ids.keys.each_slice(REVOKE_BATCH_SIZE) do |revoke_batch|
        revoke_credentials_response = credential_manager.revoke_credentials_by_id(
          destroy_reason,
          ProgrammaticAccessToken::Finder::TOKEN_TYPE,
          revoke_batch
        )

        revoke_credentials_response.responses.each do |resp|
          if resp.result == :RESULT_SUCCESS
            GitHub.dogstats.increment(STATS_KEY, tags: ["state:single_revoke_response", "result:success"])
            access_ids << verified_credential_ids[resp.credential_id]
          else
            GitHub.dogstats.increment(STATS_KEY, tags: ["state:single_revoke_response", "result:failure", "reason:#{resp.result}"])
          end
        end
      end

      GitHub.dogstats.increment(STATS_KEY, tags: ["state:end", "result:success"])

      # Returns a hash of { "success" => access_ids, "failed_verifications" => tokens }
      Result.success({ success: access_ids, failed_verifications: unverified_tokens })
    rescue ::Authnd::Proto::Error, Faraday::Error, Result::Error => err
      GitHub.dogstats.increment(STATS_KEY, tags: ["state:rescue_block", "result:failure"])
      Failbot.report!(err)
      Result.failed(err.message)
    end

    private

    def credential_manager
      ::GitHub::Authnd.credential_manager
    end

    def verify_credentials(tokens)
      ProgrammaticAccessToken::Verifier
        .perform(tokens)
    end

    def destroy_reason
      VALID_DESTROY_REASONS[@opts[:reason]]
    end
  end
end
