# typed: false
# frozen_string_literal: true

module User::AdvancedSecurityDependency
  include AdvancedSecurity::Public::Subscription
  include AdvancedSecurity::Public::Pricing
  include GitHub::Memoizer

  REPO_BATCH_SIZE = 1000

  # Can Advanced Security be enabled/disabled on repos owned by this user/org.
  def advanced_security_configurable?
    # For an organization, allow if GHAS has been purchased.
    return advanced_security_purchased? if organization?

    # For GHEC EMU/GHES user-owned repo's, GHAS is considered 'configurable' if allowed by the enterprise policy.
    ghas_for_users = AdvancedSecurity::Features::User::AdvancedSecurity.new(T.cast(self, User))
    ghas_for_users.feature_available?
  end

  # Should we enforce license limits for GHAS when a user tries to enable GHAS on repos in this user/org.
  # Generally this is true if GHAS is purchased, but if the advanced_security_circuit_breaker
  # feature flag is enabled as a temporary workaround for a bug, then we don't enforce limits even
  # if GHAS is purchased.
  def enforce_advanced_security_committers_limits?
    advanced_security_configurable? && (GitHub.enterprise? || !GitHub.flipper[:advanced_security_circuit_breaker].enabled?(advanced_security_license.billable_entity))
  end

  # Returns a page from the list of repos owned by this user/org,
  # with the following data:
  # {id:, name:, committer_count:, unique_committer_count:}
  # The list is ordered by name.
  # "unique committer count" is users who have committed to this repo but not
  # to any other repo covered by this GHAS license.
  #
  # Actual return value is a hash of the form {repos:, total_repos_count:}
  # where repos: is the page of repo data described above, and
  # total_repos_count: is the total number of GHAS repos owned by this owner
  # (total, not just the number on the current page).
  #
  # page is 0-based
  def get_advanced_security_repos_and_counts(page:, page_size: 10)
    T.bind(self, T.any(Organization, User))
    return { repos: [], total_repos_count: 0 } unless self.organization? && self.advanced_security_purchased?

    total_repos = self.repositories.count
    response = GitHub::Turboghas.client.get_repositories(
      owner_id: self.id,
      cursor: { offset: [0, page].max * page_size },
      limit: page_size,
    )
    raise StandardError.new(response.error) if response.error.present?
    {
      repos: response.data&.repositories.map do |repo|
        {
          id: repo.id,
          name: repo.name,
          committer_count: repo.active_committers,
          unique_committer_count: repo.unique_committers,
        }
      end,
      total_repos_count: response.data&.count,
      num_repos_without_ghas: total_repos - response.data&.count
    }
  end
end
