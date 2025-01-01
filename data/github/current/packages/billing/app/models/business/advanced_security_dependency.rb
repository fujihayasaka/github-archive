# typed: true
# frozen_string_literal: true

module Business::AdvancedSecurityDependency
  include AdvancedSecurity::Public::Subscription
  include AdvancedSecurity::Public::Pricing

  ORG_BATCH_SIZE = 100
  REPO_BATCH_SIZE = 1000
  NEW_REPOS_ENABLED_KEY = "advanced_security.new_business_repos"
  NEW_USER_NAMESPACE_REPOS_ENABLED_KEY = "advanced_security.new_user_namespace_repos"
  SECRET_SCANNING_NEW_REPOS_KEY = "secret_scanning.new_business_repos_enable".freeze

  def advanced_security_configurable?
    T.bind(self, Business)
    advanced_security_purchased?
  end

  def enforce_advanced_security_committers_limits?
    T.bind(self, Business)
    advanced_security_configurable? && (GitHub.enterprise? || !GitHub.flipper[:advanced_security_circuit_breaker].enabled?(advanced_security_license.billable_entity))
  end

  def enable_advanced_security_on_new_repos(actor:)
    T.bind(self, Business)
    config.enable(NEW_REPOS_ENABLED_KEY, actor)
  end

  def disable_advanced_security_on_new_repos(actor:)
    T.bind(self, Business)
    config.delete(NEW_REPOS_ENABLED_KEY, actor)
  end

  def advanced_security_enabled_on_new_repos?
    T.bind(self, Business)
    return false unless advanced_security_purchased?
    config.enabled?(NEW_REPOS_ENABLED_KEY)
  end

  def enable_advanced_security_on_new_user_namespace_repos(actor:)
    T.bind(self, Business)
    config.enable(NEW_USER_NAMESPACE_REPOS_ENABLED_KEY, actor)
  end

  def disable_advanced_security_on_new_user_namespace_repos(actor:)
    T.bind(self, Business)
    config.delete(NEW_USER_NAMESPACE_REPOS_ENABLED_KEY, actor)
  end

  def advanced_security_enabled_on_new_user_namespace_repos?
    T.bind(self, Business)
    return false unless advanced_security_purchased?
    config.enabled?(NEW_USER_NAMESPACE_REPOS_ENABLED_KEY)
  end

  def get_advanced_security_enterprise_users_and_counts(actor:, page:, page_size: 10)
    T.bind(self, Business)
    response = GitHub::Turboghas.client.get_enterprise_users(
      business_id: self.id,
      cursor: { offset: [0, page].max * page_size },
      limit: page_size,
    )
    raise StandardError.new(response.error) if response.error.present?

    feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(self)
    total = feature.num_enterprise_users
    users = feature.get_enterprise_users(user_ids: response.data&.users.map(&:id))
    users_by_id = users.index_by(&:id)

    num_without_ghas = total - response.data&.count
    num_without_ghas = 0 if num_without_ghas < 0

    {
      users: response.data&.users.map do |user|
        next if users_by_id[user.id].nil?
        {
          user: users_by_id[user.id],
          committer_count: user.active_committers,
          unique_committer_count: user.unique_committers,
        }
      end.compact,
      count: response.data&.count,
      num_without_ghas: num_without_ghas
    }
  end

  # Returns a page from the list of orgs owned by this business,
  # with the following data:
  # {organization:, committer_count:, unique_committer_count:}
  # The list is ordered by organization name.
  # "unique committer count" is users who have committed to this org but not
  # to any other org covered by this GHAS license.
  #
  # Actual return value is a hash of the form {orgs:, total_orgs_count:, num_orgs_without_ghas:}
  # where orgs: is the page of org data described above, and
  # total_orgs_count: is the total number of GHAS orgs owned by this business (total, not just the number on the current page).
  # num_orgs_without_ghas: is the number of orgs owned by this business which don't contain any repos for which GHAS is enabled
  #
  # page is 0-based
  def get_advanced_security_orgs_and_counts(page:, page_size: 10)
    T.bind(self, Business)

    total_orgs = self.organizations.count
    response = GitHub::Turboghas.client.get_organizations(
      business_id: self.id,
      cursor: { offset: [0, page].max * page_size },
      limit: page_size,
    )
    raise StandardError.new(response.error) if response.error.present?
    orgs = self.organizations.where(id: response.data&.organizations.map(&:id)).all.index_by(&:id)
    {
      orgs: response.data&.organizations.map do |org|
        {
          organization: orgs.fetch(org.id),
          committer_count: org.active_committers,
          unique_committer_count: org.unique_committers,
        }
      end,
      total_orgs_count: response.data&.count,
      num_orgs_without_ghas: total_orgs - response.data&.count
    }
  end
end
