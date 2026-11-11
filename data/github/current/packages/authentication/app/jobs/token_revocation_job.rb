# typed: true
# frozen_string_literal: true

class TokenRevocationJob < ApplicationJob
  REASON = :revocation_api
  PAT_REVOCATION_BATCH_SIZE = 50

  queue_as :token_revocation
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Don't enqueue if the feature flag is disabled
  around_enqueue do |_job, block|
    block.call if TokenRevocation::Helper.credential_revocation_enabled?
  end

  # Don't perform if the feature flag is disabled
  around_perform do |_job, block|
    block.call if TokenRevocation::Helper.credential_revocation_enabled?
  end

  sig { params(tokens: String).void }
  def perform(tokens)
    decrypted_tokens = TokenRevocation::Helper.decrypt_credentials(tokens)

    decrypted_tokens.keys.each do |token_type|
      case token_type
      when TokenRevocation::Helper::FG_PAT_CREDENTIAL
        fg_tokens = decrypted_tokens[TokenRevocation::Helper::FG_PAT_CREDENTIAL]
        UserProgrammaticAccess.throttle do
          revoke_fg_pats(fg_tokens)
        end
      when TokenRevocation::Helper::PAT_CREDENTIAL
        pat_tokens = decrypted_tokens[TokenRevocation::Helper::PAT_CREDENTIAL]
        pat_tokens&.each_slice(PAT_REVOCATION_BATCH_SIZE) do |batch|
          revoke_pats(batch)
        end
      else
        GitHub.dogstats.increment("token_revocation_job.unknown_token_type", tags: ["token_type:#{token_type}"])
      end
    end
  end

  private

  def revoke_pats(tokens)
    return if tokens.empty?

    hashed_tokens = tokens.map { |token| OauthAccessTokens::Domain.hash_token(token) }
    results = OauthAccessTokens.domain.revoke_by_hashes(hashed_tokens, REASON)

    # all tokens that were given are not valid credentials
    if results.size == 1 && results[0].is_a?(GH::Result::Error::NotFound)
      GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:failed", "token_type:#{TokenRevocation::Helper::PAT_CREDENTIAL}", "reason:tokens_not_found"])
    end

    results.each do |result|
      if result.is_a?(GH::Result::Error)
        GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:failed", "token_type:#{TokenRevocation::Helper::PAT_CREDENTIAL}", "reason:#{result.message}"])
        next
      end

      if result.is_a?(GH::Result::Ok)
        pat = result.value
        GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:success", "token_type:#{TokenRevocation::Helper::PAT_CREDENTIAL}"])

        if pat.user.nil?
          GitHub.dogstats.increment("token_revocation_job.notify", tags: ["status:failed", "reason:user_not_found", "token_type:#{TokenRevocation::Helper::PAT_CREDENTIAL}"])
          next
        end

        TokenRevocation::Helper.notify_owner_of_revoked_credential(pat.user, pat.description, TokenRevocation::Helper::PAT_CREDENTIAL)
      end
    end
  end

  def revoke_fg_pats(tokens)
    return if tokens.empty?

    response = ProgrammaticAccessTokens.domain.bulk_destroy(tokens, reason: REASON)

    unless response.success? || !!(response.value && response.value[:failed_verifications].any?)
      GitHub.logger.error("Failed to revoke fg-tokens", {
        "exception.message" => response.error,
        "code.namespace" => "TokenRevocationJob",
        "code.function" => "revoke_fg_pats",
      })
      GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:failed", "reason:authnd_revoke_error"])

      # We should kick off another job to ensure these tokens are properly checked and revoked
      tokens = (response.value && response.value[:failed_verifications].any?) ? response.value[:failed_verification] : tokens
      identified_tokens = TokenIdentification.identify_tokens(tokens)

      encrypted_tokens = TokenRevocation::Helper.encrypt_credentials(identified_tokens)

      # We don't want to enqueue this job multiple times in a test
      TokenRevocationJob.perform_later(encrypted_tokens) unless Rails.env.test?

      # If the response.value contains failed_verifications, we still need to send mailers out to the successful revocations
      # So we don't want to return here unless the entire response failed.
      return unless response.success?
    end

    # If tokens were fake, we don't return a value
    # If tokens were real, but were not found/already revoked/etc, success value will be empty
    if response.value.nil? || (response.value && response.value[:success].empty?)
      GitHub.logger.info("No fg-tokens to revoke", {
        "code.namespace" => "TokenRevocationJob",
        "code.function" => "revoke_fg_pats",
        "gh.token_type" => TokenRevocation::Helper::FG_PAT_CREDENTIAL,
        "gh.number_of_tokens" => tokens.size,
      })
      GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:failed", "token_type:#{TokenRevocation::Helper::FG_PAT_CREDENTIAL}", "reason:tokens_not_found"])
      return
    end

    response.value[:success].each do |access_id|
      GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:success", "token_type:#{TokenRevocation::Helper::FG_PAT_CREDENTIAL}"])
      access = UserProgrammaticAccess.find_by(id: access_id)
      unless access.present?
        # If the UserProgrammaticAccess record doesn't exist and we successfully revoked the token on authnd,
        # We don't need to send a mailer because we aren't showing this token to the user on the UI.
        GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:failed", "token_type:#{TokenRevocation::Helper::FG_PAT_CREDENTIAL}", "reason:access_not_found"])
        next
      end
      user = User.find_by(id: access.user_id)

      if user.nil?
        GitHub.dogstats.increment("token_revocation_job.notify", tags: ["status:failed", "reason:user_not_found", "token_type:#{TokenRevocation::Helper::FG_PAT_CREDENTIAL}"])
        next
      end

      TokenRevocation::Helper.notify_owner_of_revoked_credential(user, access.name, TokenRevocation::Helper::FG_PAT_CREDENTIAL)
    end
  end
end
