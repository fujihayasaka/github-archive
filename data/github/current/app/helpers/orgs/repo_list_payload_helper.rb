# typed: strict
# frozen_string_literal: true

module Orgs::RepoListPayloadHelper
  extend T::Sig
  include ApplicationHelper
  include LanguageHelper
  include Orgs::CustomPropertiesHelper
  include TextHelper
  include FeatureFlagHelper
  include ::Search::Repositories
  include Issues::Domain::Provider

  MAX_TOPICS_TO_SHOW = 10

  sig do
    params(
      user: T.nilable(User),
      org: ::Organization,
      query_result: MysqlSearch::ReposSearchResult,
    ).returns(RepoListPayload)
  end
  def repo_list_payload(user, org, query_result)
    user_info = user_info_payload(user, org)
    can_see_definitions = user_info && user_info[:directOrTeamMember]
    definitions = if can_see_definitions
      CustomProperties::Public.definitions_manager(org).get_definitions
    else
      []
    end

    type_filters = allowed_type_filters(user, org)

    payload = query_result_payload(query_result, user).merge({
      userInfo: user_info,
      searchable: searchable?(user, org),
      definitions: definitions_payload(definitions),
      typeFilters: type_filters.map { |id, text| { id: id, text: text } },
      compactMode: user ? user.settings.get(:orgs_repos_compact_mode) : false,
    })
  end

  sig { params(query_result: MysqlSearch::ReposSearchResult, user: T.nilable(User)).returns(QueryResultPayload) }
  def query_result_payload(query_result, user)
    repos = query_result[:repos]
    repo_ids = repos.pluck(:id)

    @open_issue_and_pr_counts = T.let({}, T.nilable(T::Hash[[Integer, T::Boolean], Integer]))
    @topics_by_repo = T.let({}, T.nilable(T::Hash[Integer, T::Array[String]]))

    unless repos.empty?
      @open_issue_and_pr_counts = if GitHub.flipper[:issue_dependency_removal].enabled?
        issues_domain.open_issue_and_pr_counts(repository_ids: repo_ids, return_nil_on_failure: true)
      else
        Repository.open_issue_and_pr_counts(repository_ids: repo_ids, return_nil_on_failure: true)
      end

      # Do not cut topics on this method, we'll do later. We need to know total topics
      @topics_by_repo = RepositoryTopic.names_for(repository_ids: repo_ids, limit_per_repo: 1000)

      GitHub::PrefillAssociations.prefill_batch_method(repos, :full_network_count)
    end

    {
      pageCount: query_result[:total_pages],
      repositories: repos.map { |repository| repo_list_item_payload(repository, user) },
      repositoryCount: query_result[:total],
    }
  end

  private

  sig { params(current_user: T.nilable(User), org: ::Organization).returns(T::Boolean) }
  def searchable?(current_user, org)
    current_user.present? || org.public_repositories.count > 0
  end

  sig { params(repository: Repository, user: T.nilable(User)).returns(RepoItemPayload) }
  def repo_list_item_payload(repository, user)
    primary_language = repository.primary_language&.name
    repo_id = T.must(repository.id)

    raise "Use only inside query_result_payload" if @topics_by_repo.nil?
    all_topics = @topics_by_repo.fetch(repo_id, [])

    participation = GitHub::RepoGraph.participation_data(repository, cache_only: true)

    {
      type: RepositoriesTypeHelper.type(
        visibility: repository.visibility,
        mirror: repository.mirror?,
        archived: repository.archived?,
        template: repository.template?,
      ),
      name: repository.name,
      owner: repository.owner_display_login,
      isFork: repository.fork?,
      description: formatted_repo_description(repository),
      allTopics: all_topics,
      primaryLanguage: primary_language ? { name: primary_language, color: language_color(Linguist::Language[primary_language]) } : nil,
      pullRequestCount: issue_count_for(repo_id, has_pull_request: true),
      issueCount: issue_count_for(repo_id, has_pull_request: false),
      starsCount: repository.stargazer_count || 0,
      forksCount: repository.network_count || 0,
      license: repository.license&.name,
      participation: participation&.dig("all"),
      lastUpdated: repository.pushed_at ? { hasBeenPushedTo: true, timestamp: repository.pushed_at } : { hasBeenPushedTo: false, timestamp: repository.created_at }
    }
  end

  sig { params(user: T.nilable(User), org: ::Organization).returns(T.nilable(UserInfo)) }
  def user_info_payload(user, org)
    return nil if user.nil?

    {
      directOrTeamMember: org.direct_or_team_member?(user),
      admin: org.adminable_by?(user),
      canCreateRepository: org.can_create_repository?(user)
    }
  end

  # Internal: Returns a hash of valid filters and their human-friendly names.
  sig { params(user: T.nilable(User), org: ::Organization).returns(T::Hash[T.untyped, T.untyped]) }
  def allowed_type_filters(user, org)
    should_internal = org.organization? && org.supports_internal_repositories? && user&.is_business_member?(org.business&.id)

    filters = { "all" => "All" }

    filters["public"] = "Public" if GitHub.public_repositories_available?
    filters["internal"] = "Internal" if should_internal
    filters["private"] = "Private" if org.can_create_repository?(user)
    filters["source"] = "Sources"
    filters["fork"] = "Forks"
    filters["archived"] = "Archived"
    filters["template"] = "Templates"
    filters
  end

  sig { params(repository_id: Integer, has_pull_request: T::Boolean).returns(T.nilable(Integer)) }
  def issue_count_for(repository_id, has_pull_request:)
    raise "Use only inside query_result_payload" unless defined?(@open_issue_and_pr_counts)
    return nil if @open_issue_and_pr_counts.nil?
    @open_issue_and_pr_counts[[repository_id, has_pull_request]].to_i
  end

  RepoListPayload = T.type_alias do
    {
      userInfo: T.nilable(UserInfo),
      searchable: T::Boolean,
      definitions: T::Array[T::Hash[String, String]],
      typeFilters: T::Array[{ id: String, text: String }],
      pageCount: Integer,
      repositories: T::Array[RepoItemPayload],
      repositoryCount: Integer,
      compactMode: T::Boolean,
    }
  end

  QueryResultPayload = T.type_alias do
    {
      pageCount: Integer,
      repositories: T::Array[RepoItemPayload],
      repositoryCount: Integer,
    }
  end

  RepoItemPayload = T.type_alias do
    {
      type: String,
      name: T.nilable(String),
      owner: String,
      isFork: T::Boolean,
      description: String,
      allTopics: T::Array[String],
      primaryLanguage: T.nilable({ name: String, color: String }),
      pullRequestCount: T.nilable(Integer),
      issueCount: T.nilable(Integer),
      forksCount: Integer,
      starsCount: Integer,
      participation: T.nilable(T::Array[Integer]),
      license: T.nilable(String),
      lastUpdated: { hasBeenPushedTo: T::Boolean, timestamp: Time }
    }
  end

  UserInfo = T.type_alias do
    {
      directOrTeamMember: T::Boolean,
      admin: T::Boolean,
      canCreateRepository: T::Boolean,
    }
  end
end
