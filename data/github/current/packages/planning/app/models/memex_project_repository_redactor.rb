# typed: strict
# frozen_string_literal: true

class MemexProjectRepositoryRedactor
  include GitHub::Memoizer

  MAX_BATCH_AUTHORIZE_SLICE_LENGTH = 100

  # Initializes a new instance of the MemexProjectRepositoryRedactor.
  #
  # @param cap_filter: Conditional Access Policy filter used for organization CAP checks.
  # @param user: The user to check for authorization of resources.
  # @param repo_ids: The array of repository ids to check for authorization.
  # @param prefilled_repositories: An optional array of previously instantiated Repository ActiveRecords.
  #    These prefilled repositories do not have to match the set of repo_ids used for authorization checks.
  #    They are simply used to help avoid redundant mySQL queries for any previously fetched repositories.
  sig do
    params(
      cap_filter: T.nilable(ConditionalAccess::Filter),
      user: T.nilable(User),
      repo_ids: T::Array[Integer],
      prefilled_repositories: T::Array[Repository],
    )
    .void
  end
  def initialize(cap_filter:, user:, repo_ids:, prefilled_repositories: [])
    @cap_filter = cap_filter
    @user = user
    @repo_ids = repo_ids
    @prefilled_repositories = prefilled_repositories
  end

  # Returns a list of repository ids authorized for viewing from given list of repositories.
  # These include public repositories and all others that have passed authzd and CAP checks.
  sig { returns(T::Array[Integer]) }
  memoize def authorized_repo_ids

    # Authorization requests require the repository objects
    repositories = T.let([], T::Array[Repository])
    if @prefilled_repositories.present?
      repositories_by_id = @prefilled_repositories.index_by(&:id)
      ids_prefilled, ids_to_query = @repo_ids.partition { |id| repositories_by_id[id].present? }
      repositories += Repository.where(id: ids_to_query) if ids_to_query.present?
      repositories += ids_prefilled.map { |id| repositories_by_id[id] } if ids_prefilled.present?
    else
      repositories = Repository.where(id: @repo_ids).to_a
    end

    # Do Conditional Access Policy (CAP) check only if the cap filter is provided
    cap_checked_repositories = @cap_filter.present? ? cap_filter_repositories(repositories) : repositories
    GitHub.dogstats.increment("memex.cap_filtering", tags: [
      "memex_cap_filtering_enabled:#{@cap_filter.present?}",
      "has_cap_filtered_items:#{cap_checked_repositories.length < repositories.length}",
    ])

    # separate out public repositories. We don't need to run authz checks on public repos.
    public_repos, private_repos = cap_checked_repositories.partition { |repo| repo.public? }

    # Run authz checks on private repos, and append the ones authorized to public
    public_repo_ids = public_repos.map(&:id)
    authorized_private_repo_ids = authz_filter_repositories(private_repos)
    public_repo_ids + authorized_private_repo_ids
  end

  # Returns a list of cap filtered repositories from given list of repositories
  # We derive a list of owner, check for cap, return repositories for which cap passed
  sig { params(repositories: T::Array[Repository]).returns(T::Array[Repository]) }
  def cap_filter_repositories(repositories)
    return [] unless repositories.present?
    return [] unless @cap_filter.present?

    owner_id_repo_map = Hash.new { |h, k| h[k] = [] }
    repositories.map do |repo|
      owner_id_repo_map[repo.owner_id] << repo
    end

    owners = User.where(id: owner_id_repo_map.keys)

    filtered_owners = T.let([], T.any(T::Set[T.untyped], []))
    GitHub.dogstats.time("memex_project_repository_redactor", tags: add_request_len_tag(["action:cap_filter_repositories"], owners)) do
      filtered_owners = Set.new(@cap_filter.authorized_resources(owners))
    end

    filtered_owners.flat_map { |owner| owner_id_repo_map[owner.id] }
  end

  # Returns a list of authorized repository ids from given list of repositories
  # We are re-using :search_repository FGP here for authorization
  sig { params(repositories: T::Array[Repository]).returns(T::Array[Integer]) }
  private def authz_filter_repositories(repositories)
    return [] unless repositories.present?

    # preload necessary data
    promises = repositories.flat_map do |r|
      [
        r.async_owner,
        r.async_business,
        r.async_owning_organization_id,
        r.async_internal?,
        r.async_writable?,
      ]
    end
    Promise.all(promises).sync

    requests = repositories.map do |repo|
      # To support GitHub Apps, attribute action.programmatic_resource_type => contents is required by the Authzd policy.
      # https://github.com/github/authzd/blob/4bd708e72c773f45beba01f6c7038a92686906e2/config/policies/repository.json#L407
      {
        actor: @user,
        subject: repo,
        action: :read_repo_contents,
        context: { "action.programmatic_resource_type" => :contents }
      }
    end

    authorized_repo_ids = []

    # For each batch of requests, do a batch authorize call and append the result to a list
    requests.each_slice(MAX_BATCH_AUTHORIZE_SLICE_LENGTH) do |request_batch|
      responses = ::Permissions::Enforcer.batch_authorize(requests: request_batch)

      request_batch.each do |request|
        next unless responses[request].allow?
        authorized_repo_ids.append(request[:subject].id)
      end
    end

    authorized_repo_ids
  end

  sig { params(tags: T::Array[String], req: T.untyped).returns(T::Array[String]) }
  def add_request_len_tag(tags, req)
    if req.present? && req.length > 0
      tags << "req_length:#{req.length}"
    else
      tags << "req_length:zero"
    end
    tags
  end
end
