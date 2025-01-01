# typed: true
# frozen_string_literal: true

class TokenRevocationJob < ApplicationJob
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

  sig { params(tokens: T::Hash[Symbol, T::Array[String]]).void }
  def perform(tokens)

    # Add logging for start of job with token counts
    tokens.keys.each do |token_type|
      case token_type
      when TokenRevocation::Helper::FG_PAT_CREDENTIAL
        UserProgrammaticAccess.throttle do
          tokens[token_type]&.each do |token|
            revoke_fg_pat token
          end
        end
      when TokenRevocation::Helper::PAT_CREDENTIAL
        OauthAccess.throttle do
          tokens[token_type]&.each do |token|
            revoke_pat token
          end
        end
      else
        GitHub.dogstats.increment("token_revocation_job.unknown_token_type", tags: ["token_type:#{token_type}"])
      end
    end
  end

  private

  def revoke_pat(token)
    return unless token.present?
    GitHub.dogstats.increment("token_revocation_job.verification", tags: ["token_type:#{TokenRevocation::Helper::PAT_CREDENTIAL}", "status:started"])
    pat = OauthAccess.find_by(hashed_token: OauthAccess.hash_token(token))

    if pat.nil?
      GitHub.dogstats.increment("token_revocation_job.verification", tags: ["token_type:#{TokenRevocation::Helper::PAT_CREDENTIAL}", "status:failed", "reason:token_not_found"])
      return
    end

    if pat.expired?
      GitHub.dogstats.increment("token_revocation_job.verification", tags: ["token_type:#{TokenRevocation::Helper::PAT_CREDENTIAL}", "status:failed", "reason:token_already_expired"])
      return
    end
    GitHub.dogstats.increment("token_revocation_job.verification", tags: ["token_type:#{TokenRevocation::Helper::PAT_CREDENTIAL}", "status:success"])

    with_write do
      pat.revoke_personal_access_token!(reason: :revocation_api)
    end

    GitHub.dogstats.increment("token_revocation_job.revoked", tags: ["token_type:#{TokenRevocation::Helper::PAT_CREDENTIAL}"])
    TokenRevocation::Helper.notify_owner_of_revoked_credential(pat.user, pat.description, TokenRevocation::Helper::PAT_CREDENTIAL)
  end

  def revoke_fg_pat(token)
    # return unless token.present?
    # # pat = OauthAccess.find_by(hashed_token: OauthAccess.hash_token(token))
    # unless pat.nil?
    #   # pat_user = pat.user
    #   with_write do
    #     # pat.revoke_personal_access_token!(reason: :revocation_api)
    #   end

    #   GitHub.dogstats.increment("token_revocation_job.revoked", tags: ["token_type:#{TokenRevocation::Helper::FG_PAT_CREDENTIAL}"])
    #   TokenRevocation::Helper.notify_owner_of_revoked_credential(pat_user, pat.description, TokenRevocation::Helper::FG_PAT_CREDENTIAL)
    # end
  end
end
