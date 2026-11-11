# typed: strict
# frozen_string_literal: true

module SecurityProducts
  class Domain < GH::Domain::Base
    include GitHub::ResilienceMixin

    DEPENDABOT_INDEX = 0
    ADVISORIES_INDEX = 1
    TOKEN_SCANNING_INDEX = 2
    CODE_SCANNING_INDEX = 3

    # Cached count of security alerts, used in the global navigation security tab for repositories.

    # The security alert count shown in the security tab is the sum of multiple underlying counts (dependabot, advisories, code scanning, token scanning),
    # and the value shown to an individual user depends on their fine-grained permissions in relation to each of these security features.

    # We cache an array of all four underlying counts at the repo level, then sum only the counts that are
    # visible to the current user, avoiding expensive permission checks when possible.
    sig { params(repository: ::Repository, viewer: T.nilable(::User)).returns(Numeric) }
    def security_alert_count_for_repo(repository, viewer)
      security_view = security_view_for(repository, viewer)
      return 0 unless security_view

      show_advisories = with_database_error_fallback(fallback: false) { security_view.show_advisories? }

      # For logged-out viewers, only advisories are visible, so we can just return a direct COUNT(*) query
      # instead of attempting to populate the shared four-count cache using a nil viewer
      if viewer.nil?
        return show_advisories ? with_database_error_fallback(fallback: 0) { security_view.security_advisories_count } : 0
      end

      counts = SecurityProducts::Cache::RepositorySecurityCountClient.new(repository).fetch do
        compute_security_counts(repository, security_view)
      end

      # Sum only the counts where the count is > zero and the user has permission to see it.
      # The expensive permission checks are skipped unless we know there's actually something to potentially show from the cached values.
      # Keyed by index constant so each permission check stays explicitly bound to its slot in `counts`.
      permission_checks = {
        DEPENDABOT_INDEX => -> { security_view.show_dependabot_alerts? },
        ADVISORIES_INDEX => -> { show_advisories },
        TOKEN_SCANNING_INDEX => -> { security_view.show_token_scanning_results? },
        CODE_SCANNING_INDEX => -> { security_view.show_code_scanning? },
      }

      permission_checks.sum do |index, permission_check|
        count = counts[index] || 0
        next 0 unless count.positive?

        with_database_error_fallback(fallback: false) { permission_check.call } ? count : 0
      end
    end

    # Force-refreshes the cached security alert counts for a repository, ensuring that
    # the next read of `security_alert_count_for_repo` reflects the current state of the underlying counts.
    sig { params(repository: ::Repository, viewer: T.nilable(::User)).void }
    def refresh_security_alert_count_cache_for_repo(repository, viewer)
      return if viewer.nil?
      security_view = security_view_for(repository, viewer)
      return unless security_view

      client = SecurityProducts::Cache::RepositorySecurityCountClient.new(repository)
      return unless client.enabled?

      client.fetch(force_refresh: true) do
        compute_security_counts(repository, security_view)
      end
    end

    # Updates a subset of the cached security alert count slots for a repository using values that have already
    # been computed elsewhere, so the cached values stay in sync without incurring redundant database queries.
    sig do
      params(
        repository: ::Repository,
        viewer: T.nilable(::User),
        dependabot_count: T.nilable(Integer),
        advisories_count: T.nilable(Integer),
        token_scanning_count: T.nilable(Integer),
        code_scanning_count: T.nilable(Integer),
      ).void
    end
    def update_security_alert_count_cache_for_repo(
      repository,
      viewer,
      dependabot_count: nil,
      advisories_count: nil,
      token_scanning_count: nil,
      code_scanning_count: nil
    )
      return if viewer.nil?

      new_values = {
        DEPENDABOT_INDEX => dependabot_count,
        ADVISORIES_INDEX => advisories_count,
        TOKEN_SCANNING_INDEX => token_scanning_count,
        CODE_SCANNING_INDEX => code_scanning_count,
      }.compact

      return if new_values.empty?

      security_view = security_view_for(repository, viewer)
      return unless security_view

      client = SecurityProducts::Cache::RepositorySecurityCountClient.new(repository)
      return unless client.enabled?

      cached_values = client.fetch { compute_security_counts(repository, security_view) }

      # Overlay the caller-supplied counts on top of the current cache values. Any
      # slot the caller did not provide (`nil`) falls through to the existing cached value.
      updated_cached_values = T.let(cached_values.dup, [Integer, Integer, Integer, Integer])
      new_values.each { |index, value| updated_cached_values[index] = value }

      # skip the Redis write when nothing actually changed
      return if updated_cached_values == cached_values

      client.store(updated_cached_values)
    end

    private

    sig { params(repository: ::Repository, viewer: T.nilable(::User)).returns(T.nilable(Navigation::Repository::SecurityView)) }
    def security_view_for(repository, viewer)
      return nil if repository.spammy?
      return nil if viewer&.spammy?

      Navigation::Repository::SecurityView.new(
        current_user: viewer,
        current_repository: repository
      )
    end

    # Computes the four cached security counts for a repository, regardless of the current user's permissions.
    # Permission filtering is applied at read time in `security_alert_count_for_repo`.
    sig { params(repository: ::Repository, security_view: Navigation::Repository::SecurityView).returns([Integer, Integer, Integer, Integer]) }
    def compute_security_counts(repository, security_view)
      dependabot_count = with_database_error_fallback(fallback: 0) do
        security_view.security_network_alerts_count
      end

      T.let([0, 0, 0, 0], [Integer, Integer, Integer, Integer]).tap do |counts_array|
        counts_array[DEPENDABOT_INDEX] = dependabot_count
        counts_array[ADVISORIES_INDEX] = security_view.security_advisories_count
        counts_array[TOKEN_SCANNING_INDEX] = security_view.security_token_scanning_count
        counts_array[CODE_SCANNING_INDEX] = security_view.security_code_scanning_count
      end
    end
  end
end
