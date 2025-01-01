# typed: true
# frozen_string_literal: true

# Public: Used to load and memoize data shown on /sponsors/explore.
class SponsorsExploreLoader
  extend T::Sig
  include GitHub::Memoizer
  include ActionView::Helpers::CaptureHelper
  include ResilienceHelper

  # Ideally, these sort options are the same as the ones in Sponsors::Explore::SortMenuComponent::HYDRO_SORT_OPTIONS.
  # If any new sort options are added here but not to the Hydro schema enum, click events in Hydro will show up with
  # sort_option=UNKNOWN.
  MOST_USED_SORT = "MOST_USED"
  LEAST_USED_SORT = "LEAST_USED"
  NEWEST_SPONSORS_PROFILE_SORT = "NEWEST_SPONSORS_PROFILE"
  OLDEST_SPONSORS_PROFILE_SORT = "OLDEST_SPONSORS_PROFILE"
  MOST_SPONSORS_SORT = "MOST_SPONSORS"
  FEWEST_SPONSORS_SORT = "FEWEST_SPONSORS"

  BATCH_SIZE = 700

  # Public: Optional Organization filter for whose dependencies should be loaded, if not the viewer's.
  sig { returns T.nilable(Organization) }
  attr_reader :org

  # filter_set - a SponsorsExploreFilterSet describing the filtering and sorting the viewer wants
  # viewer - currently authenticated User; required
  # org - optional Organization whose dependencies should be loaded if not the viewer's
  sig do
    params(
      org: T.nilable(Organization),
      filter_set: T.nilable(SponsorsExploreFilterSet),
      viewer: T.nilable(User)
    ).void
  end
  def initialize(org: nil, filter_set: nil, viewer: nil)
    @filter_set = filter_set || SponsorsExploreFilterSet.new
    @viewer = viewer
    @org = org
  end

  # Public: Is the account whose dependencies are being viewed the currently authenticated user?
  sig { returns T.nilable(T::Boolean) }
  def account_is_viewer?
    @viewer && @viewer.id == account.id
  end

  # Public: The login of the user or organization whose dependencies are loaded.
  sig { returns String }
  def account_login
    account.login
  end

  # Public: Get a sponsor to show for the specified sponsorable.
  #
  # sponsorable_id - User or Organization ID
  sig { params(sponsorable_id: Integer).returns(T.nilable(T.any(User, Organization))) }
  def first_sponsor(sponsorable_id)
    ordered_sponsorships_for_sponsorable = ordered_sponsorships_by_sponsorable_id[sponsorable_id]
    sponsorships = ordered_sponsorships_for_sponsorable.select do |sponsorship|
      sponsorship.sponsor_readable_by?(@viewer)
    end
    return unless sponsorships.any?

    first_sponsor = sponsorships.first.sponsor
    return first_sponsor unless first_sponsor == @viewer

    next_sponsorship = sponsorships.drop(1).first
    next_sponsorship&.sponsor
  end

  # Public: Get the count of how many sponsors a particular sponsorable has, including
  # private sponsors that the viewer can't know the identity of.
  #
  # sponsorable_id - User or Organization ID
  sig { params(sponsorable_id: Integer).returns(Integer) }
  def total_sponsors(sponsorable_id)
    ordered_sponsorships_by_sponsorable_id[sponsorable_id].size
  end

  # Public: Get the count of how many sponsorships by orgs a particular sponsorable has.
  #
  # sponsorable_id - User or Organization ID
  sig { params(sponsorable_id: Integer).returns(Integer) }
  def total_org_sponsors(sponsorable_id)
    sponsorships = sponsorships_by_sponsorable_id[sponsorable_id] || []
    sponsorships.count(&:from_organization?)
  end

  # Public: Check if the specified sponsorable is currently being sponsored by the account.
  #
  # sponsorable_id - User or Organization ID
  sig { params(sponsorable_id: Integer).returns(T::Boolean) }
  def sponsoring?(sponsorable_id)
    is_sponsoring_by_sponsorable_id[sponsorable_id]
  end

  # Public: Get a count of how many dependencies in the specified ecosystems the account has for the specified
  # sponsorable that represents the dependency.
  #
  # sponsorable - User or Organization associated with a dependency, either its owner or someone specified in a
  #               funding file for the dependency
  sig { params(sponsorable: T.any(User, Organization)).returns(T.nilable(Integer)) }
  def total_associated_dependencies(sponsorable)
    total_associated_dependencies_by_sponsorable[sponsorable]
  end

  # Public: Get a list of paginated repositories owned by the specified user or otherwise represented by the specified
  # user that the account depends on in their own public repos.
  #
  # sponsorable_id - Integer User or Organization ID
  #
  # Returns a WillPaginate::Collection of Repository records.
  sig { params(sponsorable_id: Integer).returns(WillPaginate::Collection) }
  def paginated_dependencies_represented_by_sponsorable(sponsorable_id)
    @paginated_dependencies_represented_by_sponsorable ||= {}
    scope = repository_scope.represented_by_sponsorable(sponsorable_id)
    result = repo_owner_dependencies_loader.dependencies(scope: scope)
    repos = result.dependencies
    repos = sort_repositories(repos) unless result.already_sorted?
    @paginated_dependencies_represented_by_sponsorable[sponsorable_id] ||= repos.paginate(page: page,
      per_page: per_page)
  end

  # Public: Get a list of all repositories owned by the specified user or otherwise represented by the specified
  # user that the account depends on in their own public repos.
  # This is used for the CSV Export functionality on the Dependencies tab
  #
  # sponsorable_id - Integer User or Organization ID
  #
  # Returns an Array of Repository records.
  sig { params(sponsorable_id: Integer).returns(T::Array[Repository]) }
  def all_dependencies_represented_by_sponsorable(sponsorable_id)
    scope = repository_scope.represented_by_sponsorable(sponsorable_id)
    result = repo_owner_dependencies_loader.dependencies(scope: scope)
    repos = result.dependencies
    repos = sort_repositories(repos) unless result.already_sorted?
    repos
  end


  # Public: Get a list of users and organizations that represent repositories the account depends on in their own
  # repositories.
  sig { returns(T::Array[T.any(User, Organization)]) }
  memoize def sponsorables_from_dependencies
    sort_sponsorables_from_dependencies(sponsorable_dependency_associated_sponsorables)
  end

  # Public: Get a paginated list of users and organizations that represent repositories the account depends on in
  # their own repos.
  #
  # Returns a WillPaginate::Collection of User and Organization records.
  sig { returns(WillPaginate::Collection) }
  memoize def paginated_sponsorables_from_dependencies
    paginated_sponsorables = sponsorables_from_dependencies.paginate(page: page, per_page: per_page)

    # Used in Sponsors::SponsorableCardComponent and Sponsors::ExploreExporter:
    GitHub::PrefillAssociations.prefill_associations(paginated_sponsorables, { sponsors_listing: :active_goal })

    paginated_sponsorables
  end

  sig { returns(Integer) }
  memoize def total_results_in_page
    paginated_sponsorables_from_dependencies.size
  end

  sig { returns(Integer) }
  memoize def total_results
    paginated_sponsorables_from_dependencies.total_entries
  end

  # Public: Get a list of Sponsors listings that are featured. Will not include listings
  # for any of the dependencies' owners, when the viewer is signed in and has dependencies.
  #
  # Returns an ActiveRecord::Relation of SponsorsListing.
  sig { returns(ActiveRecord::Relation) }
  memoize def featured_listings
    with_database_error_fallback(fallback: SponsorsListing.none) do
      if @viewer.nil?
        SponsorsListing.preload(:sponsorable).featured.limit(per_page)
      elsif total_results >= per_page
        SponsorsListing.none
      else
        limit = per_page - total_results
        SponsorsListing.preload(:sponsorable).without_sponsorable_users(sponsorable_ids_from_dependencies)
          .featured.limit(limit)
      end
    end
  end

  private

  attr_reader :filter_set

  delegate :sort_by, :page, :per_page, :direct_dependencies_only?, :ecosystems, :skip_dependency_graph_cache?,
    to: :filter_set

  def repository_scope
    scope = Repository.public_scope # only want to show public repos in Explore
    scope = scope.not_owned_by(org) if org
    scope = scope.not_owned_by(@viewer) if @viewer
    case sort_by
    when "RECENTLY_UPDATED"
      scope = scope.sorted_by(:updated, :desc)
    when "LEAST_RECENTLY_UPDATED"
      scope = scope.sorted_by(:updated, :asc)
    when "PACKAGE_NAME"
      scope = scope.sorted_by_name
    end
    scope
  end

  def sponsorable_repository_scope
    repository_scope.sponsorable # include sponsorables from funding.yml files for the repo, too
  end

  memoize def sponsorable_dependencies
    with_database_error_fallback(fallback: []) do
      result = repo_owner_dependencies_loader.dependencies(
        scope: sponsorable_repository_scope
      )
      repos = result.dependencies
      repos = sort_repositories(repos) unless result.already_sorted?
      repos
    end
  end

  memoize def ordered_sponsorships_by_sponsorable_id
    Hash.new([]).merge(ordered_sponsorships_by_sponsorable_id_pairs.to_h)
  end

  memoize def ordered_sponsorships_by_sponsorable_id_pairs
    sponsorable_ids.map do |sponsorable_id|
      sponsorships_for_sponsorable = sponsorships_by_sponsorable_id[sponsorable_id]
      ordered_sponsorships_for_sponsorable = sponsorships_for_sponsorable.sort_by do |sponsorship|
        ordered_sponsor_ids.index(sponsorship.sponsor_id)
      end
      [sponsorable_id, ordered_sponsorships_for_sponsorable]
    end
  end

  memoize def ordered_sponsor_ids
    if @viewer
      T.unsafe(User).ranked_for_ids(@viewer, scoped_ids: sponsor_ids)
    else
      sponsor_ids
    end
  end

  memoize def sponsor_ids
    lists_of_sponsorships = sponsorships_by_sponsorable_id.values
    all_sponsorships = lists_of_sponsorships.flatten
    all_sponsorships.map(&:sponsor_id).uniq
  end

  memoize def sponsorships_by_sponsorable_id
    sponsorships.each_with_object(Hash.new { |h, k| h[k] = [] }) do |sponsorship, acc|
      acc[sponsorship.sponsorable_id] << sponsorship
    end
  end

  memoize def sponsorships
    result = Sponsorship.active.with_user_or_org_sponsorable(sponsorable_ids)
      .includes(:sponsor, :tier)
      .select(:sponsor_id, :sponsorable_id, :privacy_level,
        :is_sponsor_opted_in_to_email, :subscribable_id)
      .to_a

    # Used in #first_sponsor:
    GitHub::PrefillAssociations.prefill_batch_method(result, :sponsor_readable_by?, @viewer)

    result
  end

  # Private: When dependencies were loaded in multiple batches, individual batches will have been sorted, but we need
  # to sort the combined list of them.
  #
  # repositories - an Array of Repository records
  #
  # Returns the same Array of Repository records, potentially in a different order.
  def sort_repositories(repositories)
    case sort_by
    when "RECENTLY_UPDATED"
      repositories.sort_by(&:updated_at).reverse
    when "LEAST_RECENTLY_UPDATED"
      repositories.sort_by(&:updated_at)
    when "PACKAGE_NAME"
      repositories.sort_by { |repo| repo.name.downcase }
    else
      repositories
    end
  end

  def sort_sponsorables_from_dependencies(sponsorables)
    case sort_by
    when NEWEST_SPONSORS_PROFILE_SORT
      User.sort_by_sponsors_profile_publish_date(sponsorables).reverse
    when OLDEST_SPONSORS_PROFILE_SORT
      User.sort_by_sponsors_profile_publish_date(sponsorables)
    when MOST_SPONSORS_SORT
      User.sort_by_sponsor_count(sponsorables).reverse
    when FEWEST_SPONSORS_SORT
      User.sort_by_sponsor_count(sponsorables)
    else
      sponsorables
    end
  end

  def sort_repo_counts_by_user(repo_counts_by_user)
    original_user_id_order = repo_counts_by_user.keys.map(&:id)
    case sort_by
    when MOST_USED_SORT
      repo_counts_by_user.sort_by { |user, repo_count| [-repo_count, original_user_id_order.index(user.id)] }.to_h
    when LEAST_USED_SORT
      repo_counts_by_user.sort_by { |user, repo_count| [repo_count, original_user_id_order.index(user.id)] }.to_h
    else
      repo_counts_by_user
    end
  end

  def account
    org || @viewer
  end

  # Private: Get a hash of the how many dependencies in the specified ecosystems the account has, grouped by each
  # sponsorable that represents the dependency.
  #
  # Returns a Hash of { User => Integer }.
  memoize def total_associated_dependencies_by_sponsorable
    sponsorables_by_repo_id = associated_sponsorables_by_dependency_id_for(sponsorable_dependencies)
    repo_counts_by_sponsorable = sponsorable_dependencies.each_with_object(Hash.new(0)) do |repo, hash|
      sponsorables = sponsorables_by_repo_id[repo.id] || []
      sponsorables.each do |sponsorable|
        hash[sponsorable] += 1
      end
    end
    sort_repo_counts_by_user(repo_counts_by_sponsorable)
  end

  # Private: All sponsorable users and organizations that represent any dependency, either because they own it
  # or because they are listed in the funding.yml for that dependency.
  #
  # Returns an Array of User records.
  memoize def sponsorable_dependency_associated_sponsorables
    total_associated_dependencies_by_sponsorable.keys
  end

  def associated_sponsorables_by_dependency_id_for(dependencies)
    @associated_sponsorables_by_dependency_id ||= {}

    dependency_ids = dependencies.map(&:id).to_set
    dependency_ids_to_look_up = dependency_ids - @associated_sponsorables_by_dependency_id.keys.to_set

    if dependency_ids_to_look_up.any?
      sponsorable_ids_by_dependency_id = sponsorable_ids_by_dependency_id_for(dependency_ids_to_look_up)
      sponsorables_by_id = sponsorables_by_id_from(sponsorable_ids_by_dependency_id)

      sponsorable_ids_by_dependency_id.each do |dependency_id, sponsorable_ids|
        @associated_sponsorables_by_dependency_id[dependency_id] ||= Set.new

        sponsorable_ids.each do |sponsorable_id|
          sponsorable = sponsorables_by_id[sponsorable_id]
          @associated_sponsorables_by_dependency_id[dependency_id].add(sponsorable)
        end
      end
    end

    @associated_sponsorables_by_dependency_id.slice(*dependency_ids)
  end

  def sponsorables_by_id_from(sponsorable_ids_by_dependency_id)
    sponsorable_ids = sponsorable_ids_by_dependency_id.values.flatten.uniq
    sponsorables_by_id = {}

    sponsorable_ids.each_slice(BATCH_SIZE) do |sponsorable_ids_in_batch|
      sponsorables_by_id.merge!(User.where(id: sponsorable_ids_in_batch).filter_spam_for(@viewer).index_by(&:id))
    end

    sponsorables_by_id
  end

  def sponsorable_ids_by_dependency_id_for(repository_ids)
    sponsorable_ids_by_dependency_id = {}

    repository_ids.each_slice(BATCH_SIZE) do |_repo_ids_in_batch|
      id_pairs = RepositorySponsorable.for_repository(repository_ids).pluck(:repository_id, :sponsorable_id)
      id_pairs.each do |repo_id, sponsorable_id|
        sponsorable_ids_by_dependency_id[repo_id] ||= []
        sponsorable_ids_by_dependency_id[repo_id] << sponsorable_id
      end
    end

    sponsorable_ids_by_dependency_id
  end

  memoize def repo_owner_dependencies_loader
    Repository::OwnerDependenciesLoader.new(
      public_only: only_find_dependencies_from_public_repos?,
      direct_only: direct_dependencies_only?,
      owner_id: account&.id,
      package_managers: ecosystems,
      sort_by: sort_by,
      repository_ids: repository_ids_to_check_for_dependencies,
      viewer: @viewer,
    )
  end

  memoize def repository_ids_to_check_for_dependencies
    with_database_error_fallback(fallback: []) do
      account.repository_ids_to_check_for_sponsorable_dependencies(viewer: @viewer)
    end
  end

  memoize def account_adminable_by_viewer?
    @viewer.present? && @viewer.id == account.id ||
      # Only org owners, but not org billing managers, can see dependencies that the org's private
      # repos use:
      org.present? && T.must(org).adminable_by?(@viewer)
  end

  def only_find_dependencies_from_public_repos?
    if repository_ids_to_check_for_dependencies.present?
      # Don't need to limit to just checking the owner's public repositories for dependencies since we're
      # passing an explicit list of the owner's repositories that the viewer can access:
      false
    else
      !account_adminable_by_viewer?
    end
  end

  memoize def is_sponsoring_by_sponsorable_id
    with_database_error_fallback(fallback: Hash.new(false)) do
      Sponsorship.sponsor_status_by_sponsorable_id(
        sponsorable_ids: sponsorable_ids,
        sponsor_id: account.id,
        viewer: @viewer,
      )
    end
  end

  memoize def sponsorable_ids_from_dependencies
    if @viewer
      sponsorable_dependency_associated_sponsorables.map(&:id).to_set
    else
      Set.new
    end
  end

  memoize def sponsorable_ids
    sponsorable_ids_from_dependencies | Set.new(featured_listings.map(&:sponsorable_id))
  end
end
