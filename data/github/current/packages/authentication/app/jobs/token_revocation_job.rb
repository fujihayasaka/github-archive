# typed: true
# frozen_string_literal: true

class TokenRevocationJob < ApplicationJob
  REASON = :revocation_api
  PAT_REVOCATION_BATCH_SIZE = 50
  OAUTH_LOOKUP_BATCH_SIZE = 200
  OAUTH_REVOCATION_BATCH_SIZE = 50
  OAUTH_TOKEN_TYPES = [
    TokenRevocation::Helper::OAUTH_APP_TOKEN_CREDENTIAL,
    TokenRevocation::Helper::GH_APP_U2S_CREDENTIAL,
    TokenRevocation::Helper::GH_APP_REFRESH_TOKEN_CREDENTIAL,
  ].freeze

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

    decrypted_tokens.each do |token_type, token_list|
      # avoid processing empty token lists
      next if token_list.blank?

      case token_type
      when TokenRevocation::Helper::FG_PAT_CREDENTIAL
        UserProgrammaticAccess.throttle do
          revoke_fg_pats(token_list)
        end
      when TokenRevocation::Helper::PAT_CREDENTIAL
        token_list.each_slice(PAT_REVOCATION_BATCH_SIZE) do |batch|
          revoke_pats(batch)
        end
      when TokenRevocation::Helper::OAUTH_APP_TOKEN_CREDENTIAL
        if TokenRevocation::Helper.credential_revocation_oauth_app_tokens_enabled?
          revoke_oauth_tokens(token_list, TokenRevocation::Helper::OAUTH_APP_TOKEN_CREDENTIAL)
        else
          GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:skipped", "token_type:#{TokenRevocation::Helper::OAUTH_APP_TOKEN_CREDENTIAL}", "reason:feature_flag_disabled"])
        end
      when TokenRevocation::Helper::GH_APP_U2S_CREDENTIAL
        if TokenRevocation::Helper.credential_revocation_u2s_tokens_enabled?
          revoke_oauth_tokens(token_list, TokenRevocation::Helper::GH_APP_U2S_CREDENTIAL)
        else
          GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:skipped", "token_type:#{TokenRevocation::Helper::GH_APP_U2S_CREDENTIAL}", "reason:feature_flag_disabled"])
        end
      when TokenRevocation::Helper::GH_APP_S2S_CREDENTIAL
        if TokenRevocation::Helper.credential_revocation_s2s_tokens_enabled?
          # TODO: wire up S2S token revocation
        else
          GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:skipped", "token_type:#{TokenRevocation::Helper::GH_APP_S2S_CREDENTIAL}", "reason:feature_flag_disabled"])
        end
      when TokenRevocation::Helper::GH_APP_REFRESH_TOKEN_CREDENTIAL
        if TokenRevocation::Helper.credential_revocation_refresh_tokens_enabled?
          revoke_oauth_tokens(token_list, TokenRevocation::Helper::GH_APP_REFRESH_TOKEN_CREDENTIAL)
        else
          GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:skipped", "token_type:#{TokenRevocation::Helper::GH_APP_REFRESH_TOKEN_CREDENTIAL}", "reason:feature_flag_disabled"])
        end
      else
        GitHub.dogstats.increment("token_revocation_job.unknown_token_type", tags: ["token_type:#{token_type}"])
      end
    end
  end

  private

  def revoke_pats(tokens)
    hashed_tokens = tokens.map { |token| OauthAccessTokens::Domain.hash_token(token) }
    results = OauthAccessTokens.domain.revoke_by_hashes(hashed_tokens, REASON)

    # all tokens that were given are not valid credentials
    if results.size == 1 && results[0].is_a?(GH::Result::Error::NotFound)
      GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:failed", "token_type:#{TokenRevocation::Helper::PAT_CREDENTIAL}", "reason:tokens_not_found"])
      return
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
    response = ProgrammaticAccessTokens.domain.bulk_destroy(tokens, reason: REASON)

    unless response.success? || !!(response.value && response.value[:failed_verifications].any?)
      GitHub.logger.error("Failed to revoke fg-tokens", {
        "exception.message" => response.error,
        "code.namespace" => "TokenRevocationJob",
        "code.function" => "revoke_fg_pats",
      })
      GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:failed", "reason:authnd_revoke_error"])

      # We should kick off another job to ensure these tokens are properly checked and revoked
      tokens = (response.value && response.value[:failed_verifications].any?) ? response.value[:failed_verifications] : tokens
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

  def revoke_oauth_tokens(tokens, token_type)
    raise ArgumentError, "token_type must be one of #{OAUTH_TOKEN_TYPES}" unless OAUTH_TOKEN_TYPES.include?(token_type)

    token_type_tag = "token_type:#{token_type}"

    authorization_access_counts = oauth_authorization_access_counts(tokens, token_type)

    if authorization_access_counts.empty?
      GitHub.dogstats.count("token_revocation_job.revoke", tokens.size, tags: ["status:failed", token_type_tag, "reason:tokens_not_found"])
      return
    end

    authorization_access_counts.each_slice(OAUTH_REVOCATION_BATCH_SIZE) do |batch|
      # batch is an array of [authorization_id, access_count]
      notifications = []

      begin
        OauthAccessTokens.domain.with_write do
          batch_auth_ids = batch.map(&:first)
          authorizations_by_id = OauthAuthorization.where(id: batch_auth_ids).includes(:user, :application).index_by(&:id)

          # access_count is the number of submitted tokens that matched this
          # authorization, not the total number of accesses belonging to it.
          batch.each do |authorization_id, access_count|
            authorization = authorizations_by_id[authorization_id]

            unless authorization.present?
              GitHub.dogstats.count("token_revocation_job.revoke", access_count, tags: ["status:failed", token_type_tag, "reason:authorization_not_found"])
              next
            end

            user = authorization.user
            app_name = authorization.application&.name || "Unknown application"
            scopes = authorization.scopes

            # Throttle per-destroy so Freno is checked before each write operation,
            # preventing DB overload when processing a large batch of authorizations.
            #
            # Destroy the authorization - this will cascade delete all associated tokens.
            # We destroy even if the specific token is expired because:
            # 1. The authorization may have other active tokens
            # 2. The leak indicates the app connection may be compromised
            begin
              OauthAuthorization.throttle_with_retry(max_retry_count: 3) do
                authorization.destroy_with_explanation(REASON, entry_point: :token_revocation_job)
              end
            rescue ActiveRecord::RecordNotFound
              GitHub.dogstats.count("token_revocation_job.revoke", access_count, tags: ["status:failed", token_type_tag, "reason:already_destroyed"])
              next
            end

            GitHub.dogstats.count("token_revocation_job.revoke", access_count, tags: ["status:success", token_type_tag])

            notifications << { user: user, app_name: app_name, scopes: scopes }
          end
        end
      rescue => e
        # Send notifications for authorizations already destroyed before re-raising.
        # On retry those authorizations will be gone and notifications would be lost.
        GitHub.dogstats.increment("token_revocation_job.revoke", tags: ["status:failed", token_type_tag, "reason:unexpected_error"])
        send_oauth_notifications(notifications, token_type_tag, token_type)
        raise
      end

      send_oauth_notifications(notifications, token_type_tag, token_type)
    end
  end

  def send_oauth_notifications(notifications, token_type_tag, token_type)
    notifications.each do |notification|
      if notification[:user].nil?
        GitHub.dogstats.increment("token_revocation_job.notify", tags: ["status:failed", "reason:user_not_found", token_type_tag])
        next
      end

      TokenRevocation::Helper.notify_owner_of_revoked_credential(
        notification[:user],
        notification[:app_name],
        token_type,
        scopes: notification[:scopes],
      )
    end
  end

  # Look up which authorizations are affected and how many accesses each has.
  #
  # @param tokens [Array<String>] Raw (unhashed) token strings
  # @param token_type [Symbol] The credential type being revoked
  # @return [Hash{authorization_id => count of tokens}] Map of authorization_id to matched access count
  def oauth_authorization_access_counts(tokens, token_type)
    is_refresh_token = token_type == TokenRevocation::Helper::GH_APP_REFRESH_TOKEN_CREDENTIAL

    # Refresh tokens use a different hashing algorithm than OAuth/U2S tokens.
    hashed_tokens = tokens.map do |token|
      is_refresh_token ? RefreshToken.hash_token(token) : OauthAccessTokens::Domain.hash_token(token)
    end
    hashed_tokens.uniq!

    # Look up authorization IDs in batches, reading from the primary to avoid stale replicas.
    # Refresh tokens require a cross-DB lookup (IntegrationsCollab → Integrations).
    # Wrap the entire loop in a single with_write block to avoid repeated connection role switches.
    OauthAccessTokens.domain.with_write do
      hashed_tokens.each_slice(OAUTH_LOOKUP_BATCH_SIZE).each_with_object({}) do |batch, counts|
        auth_ids = if is_refresh_token
          OauthAccessTokens.domain.authorization_ids_by_refresh_token_hashes(batch)
        else
          OauthAccessTokens.domain.authorization_ids_by_hashes(batch)
        end
        # Tally duplicates so we can report accurate per-authorization revocation counts.
        counts.merge!(auth_ids.tally) { |_, old, new_val| old + new_val }
      end
    end
  end
end
