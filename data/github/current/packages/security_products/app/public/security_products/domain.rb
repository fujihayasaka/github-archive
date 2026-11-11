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
      return 0 if repository.spammy?
      return 0 if viewer&.spammy?

      security_view = Navigation::Repository::SecurityView.new(
        current_user: viewer,
        current_repository: repository
      )

      show_advisories = with_database_error_fallback(fallback: false) { security_view.show_advisories? }

      # For logged-out viewers, only advisories are visible, so we can just return a direct COUNT(*) query
      # instead of attempting to populate the shared four-count cache using a nil viewer
      if viewer.nil?
        return show_advisories ? with_database_error_fallback(fallback: 0) { security_view.security_advisories_count } : 0
      end

      counts = SecurityProducts::Cache::RepositorySecurityCountClient.new(repository).fetch do
        dependabot_count = with_database_error_fallback(fallback: 0) do
          if repository.vulnerability_alerts_enabled?
            if !security_view.dependabot_alerts_use_es?
              RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(repository: repository, state: :open).total_entries
            else
              security_view.security_network_alerts_count
            end
          else
            0
          end
        end

        # Each of these counts gets cached regardless of the current user's permissions
        # (but we will only return the sum of the counts that the user has permission to see).
        T.let([0, 0, 0, 0], [Integer, Integer, Integer, Integer]).tap do |counts_array|
          counts_array[DEPENDABOT_INDEX] = dependabot_count
          counts_array[ADVISORIES_INDEX] = security_view.security_advisories_count
          counts_array[TOKEN_SCANNING_INDEX] = security_view.security_token_scanning_count
          counts_array[CODE_SCANNING_INDEX] = security_view.security_code_scanning_count
        end
      end

      # Sum only the counts where the count is > zero and the user has permission to see it.
      # The expensive permission checks are skipped unless we know there's actually something to potentially show from the cached values.
      {
        DEPENDABOT_INDEX => -> { security_view.show_dependabot_alerts? },
        ADVISORIES_INDEX => -> { show_advisories },
        TOKEN_SCANNING_INDEX => -> { security_view.show_token_scanning_results? },
        CODE_SCANNING_INDEX => -> { security_view.show_code_scanning? },
      }.sum do |index, permission_check|
        count = counts[index] || 0
        next 0 unless count > 0

        with_database_error_fallback(fallback: false) { permission_check.call } ? count : 0
      end
    end
  end
end
