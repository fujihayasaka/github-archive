# typed: strict
# frozen_string_literal: true

##
# Service for handling licensing and committer data for Quick Setup.
# Provides methods to fetch committer information for billing purposes
# when enabling security features on repositories.
class SecurityProductsEnablement::QuickSetupService::LicensingService
  # Committer data constants
  DEFAULT_COMMITTER_LIMIT = T.let(500, Integer)

  sig { returns(Organization) }
  attr_reader :organization

  sig { params(organization: Organization).void }
  def initialize(organization:)
    @organization = organization
  end

  # Returns the number of additional licenses that would be consumed if the given SKU
  # were enabled for all repositories in the organization.
  #
  # @param sku [GitHub::Turboghas::SKU] The billing SKU (Bundled, CodeSecurity, or SecretSecurity)
  # @return [Integer] Number of additional licenses that would be consumed
  sig { params(sku: GitHub::Turboghas::SKU).returns(Integer) }
  def increased_license_usage_for_sku(sku)
    organization.advanced_security_license_for_sku(sku:).seat_usage_increase_if_enabled_for_all_repos
  end

  # Fetches committer data for a specific SKU
  # Returns a hash mapping repository IDs to arrays of committer IDs that would be added to billing.
  #
  # @param repositories [Array<Hash>] Array of repository hashes with :id, :visibility, :archived keys
  # @param sku [GitHub::Turboghas::SKU] The billing SKU (Bundled, CodeSecurity, or SecretSecurity)
  # @return [Hash<Integer, Array<Integer>>] Map of repository ID to array of additional committer IDs
  sig do
    params(
      repositories: T::Array[T::Hash[Symbol, T.untyped]],
      sku: GitHub::Turboghas::SKU
    ).returns(T::Hash[Integer, T::Array[Integer]])
  end
  def fetch_committer_data_for_feature(repositories, sku)
    # Filter to billable repos only (excludes archived; excludes public on dotcom but not GHES)
    billable_repo_ids = repositories.filter_map { |r| r[:id] if billable_repo?(r) }

    return {} if billable_repo_ids.empty?

    # Fetch additional committers (committers that would be added to billing if feature is enabled)
    committers_for_repo_ids(billable_repo_ids, sku)
  end

  private

  # Determines if a repository should be included in billing calculations.
  # On dotcom, public repos are free for GHAS, so exclude them.
  # On GHES, all repos (including public) are billed.
  sig { params(repo: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def billable_repo?(repo)
    return false if repo[:archived]
    return true if GitHub.enterprise? # GHES bills all repos including public
    repo[:visibility] != "public"     # dotcom: exclude public repos
  end

  # Fetches committer IDs for a set of repositories and a specific SKU.
  #
  # @param repo_ids [Array<Integer>] Repository IDs to fetch committers for
  # @param sku [GitHub::Turboghas::SKU] The billing SKU
  # @return [Hash<Integer, Array<Integer>>] Map of repository ID to array of committer IDs
  sig do
    params(
      repo_ids: T::Array[Integer],
      sku: GitHub::Turboghas::SKU
    ).returns(T::Hash[Integer, T::Array[Integer]])
  end
  def committers_for_repo_ids(repo_ids, sku)
    result = T.let({}, T::Hash[Integer, T::Array[Integer]])
    return result if repo_ids.empty?

    cursor = T.let(nil, T.nilable(Turboghas::Proto::Cursor))
    begin
      loop do
        response = GitHub::Turboghas.check_error(
          GitHub::Turboghas.client.get_committers_for_owner(Turboghas::Proto::GetCommittersForOwnerRequest.new(
            owner_id: organization.id,
            committer_type: :ADDITIONAL_COMMITTERS,
            features: sku.features,
            repository_ids: repo_ids,
            cursor: cursor,
            limit: DEFAULT_COMMITTER_LIMIT,
          ))
        )

        response.committers.each { |committer| (result[committer.repository_id] ||= []).push(committer.id) }

        cursor = response.next_cursor
        break if cursor.nil?
      end
    rescue GitHub::Turboghas::ResponseError, Faraday::ConnectionFailed, Faraday::TimeoutError => e
      GitHub.logger.warn(
        "Failed to fetch additional committers",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.org.id": organization.id,
        "gh.org.login": organization.display_login,
        "gh.security_products_enablement.sku": sku.to_param,
        "gh.security_products_enablement.repo_count": repo_ids.size,
        "error.message": e.message,
        "error.class": e.class.name
      )
    end

    result
  end
end
