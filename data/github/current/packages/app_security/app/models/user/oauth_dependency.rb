# typed: true
# frozen_string_literal: true

module User::OauthDependency
  extend T::Helpers

  requires_ancestor { User }

  # Public: Queue a job to revoke all OAuth tokens for a user of a specified
  # kind.
  #
  # kind - The kind of tokens to remove (either third_party or personal_tokens)
  #
  # Returns truthy if the job was enqueued successfully and falsey otherwise.
  def async_revoke_oauth_tokens(kind)
    RemoveOauthUserTokensJob.perform_later(id, kind)
  end

  # Public: Revoke all OAuth tokens for a user of a specified kind.
  #
  # kind            - The kind of tokens to remove (either third_party or
  #                   personal_tokens)
  # should_throttle - Whether to use the DB throttler (only asynchronous jobs
  #                   should).
  # limit           - The maximum number of tokens to remove. (Because it can
  #                   take a prolonged amount of time to remove a large number
  #                   of tokens, setting a limit is useful for splitting the
  #                   work into smaller, faster-running method invocations. By
  #                   default, no limit is applied, and therefore all tokens are
  #                   removed.
  #
  # Returns nothing
  def revoke_oauth_tokens(kind, should_throttle: false, limit: nil, entry_point: nil)
    authorizations = authorizations_for_kind(kind)
    authorizations = authorizations.limit(limit) if limit.present?

    # An OAuth application can have more than one token for a user. The number
    # of tokens is not important, so we keep track of the number of authorized
    # applications that are revoked. For personal access tokens, this will
    # represent the number of personal access tokens revoked.
    revoked = if should_throttle
      throttle do
        revoke_oauth_authorizations(authorizations, entry_point: entry_point)
      end
    else
      revoke_oauth_authorizations(authorizations, entry_point: entry_point)
    end

    instrument :revoke_oauth_tokens, kind: kind, revoked: revoked
  end

  # Public: Revoke a specified list of OAuth tokens for a user.
  #
  # token_ids - An array of the IDs for the OAuth Tokens we want to revoke sessions for.
  # should_throttle - Whether to use the DB throttler (only asynchronous jobs should).
  #
  # Returns nothing
  def revoke_specific_oauth_tokens(token_ids, should_throttle: false, entry_point: nil)
    # In this case we're going to revoke accesses instead of authorizations, but
    # we can still use revoke_oauth_authorizations since
    # OauthAccess#destroy_with_explanation exists.
    accesses = oauth_accesses.where(id: token_ids)

    # An OAuth application can have more than one token for a user. The number
    # of tokens is not important, so we keep track of the number of authorized
    # applications that are revoked.
    revoked = if should_throttle
      throttle do
        revoke_oauth_authorizations(accesses, entry_point: entry_point)
      end
    else
      revoke_oauth_authorizations(accesses, entry_point: entry_point)
    end

    instrument :revoke_oauth_tokens, revoked: revoked
  end

  # Public: Revoke all OAuth tokens for a user for a specified list of applications.
  #
  # app_ids - An array of the IDs for the OAuth Applications we want to revoke sessions for.
  # should_throttle - Whether to use the DB throttler (only asynchronous jobs should).
  #
  # Returns nothing
  def revoke_oauth_tokens_for_oauth_apps(app_ids, should_throttle: false, entry_point: nil)
    authorizations = authorizations_for_oauth_app_ids(app_ids)

    # An OAuth application can have more than one token for a user. The number
    # of tokens is not important, so we keep track of the number of authorized
    # applications that are revoked.
    revoked = if should_throttle
      throttle do
        revoke_oauth_authorizations(authorizations, entry_point: entry_point)
      end
    else
      revoke_oauth_authorizations(authorizations, entry_point: entry_point)
    end

    instrument :revoke_oauth_tokens, revoked: revoked
  end

  # Public: Get authorizations for this user for a specific kind.
  #
  # kind - The kind of tokens (either third_party or personal_tokens or github_apps)
  #
  # Returns a connection to OauthAuthorization
  def authorizations_for_kind(kind)
    # kind is generally expected to be a string, but we support symbols just in
    # case.
    kind = kind.to_s
    case kind
    when "all"
      oauth_authorizations
    when "third_party"
      oauth_authorizations.third_party
    when "personal_tokens"
      oauth_authorizations.personal_tokens
    when "github_apps"
      oauth_authorizations.github_apps
    else
      raise ArgumentError, "kind must be 'third_party', 'personal_tokens', or 'github_apps'"
    end
  end

  # Public: Get personal access tokens for this user that can be used for account recovery.
  #
  # max_created_at - The maximum created_at date for tokens to be considered eligible for recovery.
  # limit - maximum number of results to return
  #
  # Returns the tokens for user that are eligible to be used for account recovery.
  def personal_tokens_for_account_recovery(max_created_at, limit: 200)
    time_filtered_tokens = oauth_accesses.personal_tokens.where("(expires_at_timestamp > ? OR expires_at_timestamp IS NULL) AND created_at <= ?", Time.current.to_i, max_created_at)
    time_filtered_tokens = time_filtered_tokens.order(created_at: :desc)
    time_filtered_tokens = time_filtered_tokens.limit(limit) if limit.present?
    scoped_tokens = time_filtered_tokens.filter { |token| !token.scopes.nil? && (token.scopes.include? "repo") }

    scoped_tokens
  end

  # Public: Is the current user allowed to request the "site_admin" scope?
  #
  # In short, we want dotcom site admins to create PATs with this scope
  # exclusively out of admin hosts.
  #
  # Full context: https://github.com/github/github/pull/218264
  def site_admin_scope_allowed?
    return false unless site_admin?
    return GitHub::CurrentTenant.stafftools_tenant? if GitHub.multi_tenant_enterprise?
    GitHub.admin_host? || GitHub.enterprise? || Rails.env.development?
  end

  private

  # Private: Revoke a set of OAuth token authorizations.
  #
  # authorizations - The OAuth Authorization records or a connection to them.
  #
  # Note: The goal is to delete OAuth tokens, but all tokens belong to an
  # OauthAuthorization and there is a dependent destroy relationship between
  # an authorization and a token. So, we iterate over all of the authorizations
  # and destroy those in order to destroy all tokens. This is an implementation
  # detail, and is why this is hidden in a private method.
  #
  # Returns the number of authorizations revoked.
  def revoke_oauth_authorizations(authorizations, entry_point: nil)
    revoked = 0
    authorizations.find_each do |authorization|
      if authorization.destroy_with_explanation(:web_user, entry_point: entry_point)
        revoked += 1
      end
    end
    revoked
  end

  # Private: Get authorizations for this user for a specific kind.
  #
  # app_ids - An array of the OAuth Application IDs.
  #
  # Returns a connection to OauthAuthorization
  def authorizations_for_oauth_app_ids(app_ids)
    oauth_authorizations.where(application_id: app_ids, application_type: "OauthApplication")
  end
end
