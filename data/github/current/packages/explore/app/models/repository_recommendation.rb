# typed: true
# frozen_string_literal: true

class RepositoryRecommendation
  attr_reader :repository, :score, :reason, :algorithm_version

  # If Munger is unavailable, trending repositories will be returned instead. This caps how many
  # of those we will get.
  MAX_TRENDING_REPOS_TO_FETCH = 100

  def initialize(repository:, score: 0, reason: nil, algorithm_version: nil, generated_at: nil)
    @repository = repository
    @score = score
    @algorithm_version = algorithm_version
    @generated_at = if generated_at
      Time.at(generated_at).to_datetime
    end
    @reason = if self.class.valid_reasons.include?(reason)
      reason
    else
      T.must(Platform::Enums::RepositoryRecommendationReason.values["OTHER"]).value
    end
  end

  # Public: Returns a list of valid reasons for a repository to be recommended.
  #
  # Returns an Array of lowercase Strings.
  def self.valid_reasons
    Platform::Enums::RepositoryRecommendationReason.values.values.map(&:value)
  end

  # Public: Returns the date and time at which this recommendation was generated.
  def generated_at
    if @generated_at.present?
      Time.at(@generated_at).to_datetime
    end
  end

  # Public: Returns true if this repository can be recommended to users.
  def can_be_recommended?
    return false unless candidate_for_recommendation?

    # Ensure repository has not been opted out of being recommended.
    !RepositoryRecommendationOptOut.exists?(repository_id: repository)
  end

  # Public: Returns true if this repository can be opted back in to be recommended.
  def can_opt_in?
    return false unless candidate_for_recommendation?

    # Ensure repository has been opted out of being recommended.
    RepositoryRecommendationOptOut.exists?(repository_id: repository)
  end

  # Private: Sentence fragments describing each non-OTHER repository recommendation
  # reason. Synchronized with RepositoryRecommendationReason enum values by
  # unit test.
  EXPLANATIONS = {
    "trending" => "Trending right now on GitHub",
    "topics" => "Based on topics you're interested in",
    "popular" => "Popular on GitHub",
    "starred" => "Based on repositories you’ve starred",
    "followed" => "Based on people you follow",
    "viewed" => "Based on repositories you’ve viewed",
    "contributed" => "Based on your public repository contributions",
  }.freeze

  # Public: Generate a human-presentable sentence summarizing why a specific
  # recommendation has been made.
  def explain
    EXPLANATIONS.fetch(reason, "This repository might interest you")
  end

  def ==(other)
    self.class == other.class &&
      repository.id == other.repository.id &&
      score == other.score &&
      reason == other.reason
  end
  alias_method :eql?, :==

  # Private: Returns a Dogstats key for executing the given step.
  #
  # Returns a String.
  def self.time_key_for(process_name)
    "repository_recommendations.#{process_name}.duration"
  end
  private_class_method :time_key_for

  # Public: Given a JSON response from Munger, this will extract repository recommendations.
  # Returns an unfiltered list of recommendations that should be filtered to exclude spammy and
  # private repositories, as well as to exclude recommendations that the user has dismissed. The
  # result may also contain duplicates.
  #
  # user - a User instance
  # json - a JSON response from the Munger service as a hash
  #
  # Returns an Array of RepositoryRecommendations.
  def self.recommendations_from_json(user, json)
    recommendation_data = json["recommendations"]

    repo_ids = recommendation_data.map { |rec| rec["repository_id"] }
    repositories_by_id = GitHub.dogstats.time(time_key_for("fetch_repositories")) do
      Repository.where(id: repo_ids).index_by(&:id)
    end

    recommendations = recommendation_data.map do |rec|
      repository = repositories_by_id[rec["repository_id"]]

      new(score: rec["score"], repository: repository, reason: rec["reason"].try(:downcase),
          algorithm_version: rec["algorithm_version"], generated_at: rec["generated_at"])
    end

    recommendations
  end

  # Public: Given a list of recommendations, this returns a Promise resolving to a subset of those
  # that should be visible.
  #
  # This excludes repositories the user has already dismissed, spammy repositories, private
  # repositories, and recommendations for repositories that do not exist.
  #
  # Returns an Array of RepositoryRecommendation instances.
  def self.filter(recommendations, user:, mobile_sort_order: false)
    recommended_repo_ids = recommendations.map(&:repository_id).compact
    opted_out_repo_ids = opted_out_repository_ids(recommended_repo_ids)
    network_restricted_repo_ids = network_restricted_repository_ids(recommended_repo_ids)
    starred_repo_ids = user.starred_repository_ids
    hidden_from_discovery_repo_ids = hidden_from_discovery_repository_ids(recommended_repo_ids)

    GitHub.dogstats.time(time_key_for("filter_recommendations")) do
      # First, do the inexpensive checks
      filtered_recommendations = recommendations.reject do |recommendation|
        repo = recommendation.repository
        if repo
          repo.private? || # only recommend public repositories
            repo.user_hidden? # exclude repositories with spammy owners
        else
          true # reject recommendations where the repository no longer exists
        end
      end

      repos = filtered_recommendations.map(&:repository)

      # Batch load to avoid N+1 queries from Repository#archived?
      archived_results = Promise.all(repos.map(&:async_archived?)).sync
      filtered_recommendations.reject!.with_index do |_recommendation, i|
        archived_results[i]
      end

      filtered_recommendations.reject! do |recommendation|
        repo = recommendation.repository

        hidden_from_discovery_repo_ids.include?(repo.id) || # exclude hidden repositories
          starred_repo_ids.include?(repo.id) || # exclude repositories starred by user
          opted_out_repo_ids.include?(repo.id) || # exclude opted-out repositories
          network_restricted_repo_ids.include?(repo.id) || # exclude "sewer" repositories
          repo.access.disabled? # exclude disabled repositories
      end

      if mobile_sort_order
        filtered_recommendations = filtered_recommendations
        .sort_by { |recommendation| self.mobile_sort_by(recommendation.repository) }
        .reverse
        .lazy
      end

      filtered_recommendations.uniq(&:repository_id)
    end
  end

  # Private: Returns a repo sorting order for mobile recommendations.
  #
  # Sorts in the following order:
  #   1. Has a custom open graph image
  #   2. Belongs to an organization
  #   3. All other repositories
  def self.mobile_sort_by(repo)
    uses_custom_image = repo.async_uses_custom_open_graph_image?.sync ? 1 : 0
    in_organization = repo.async_in_organization?.sync ? 1 : 0

    [uses_custom_image, in_organization]
  end
  private_class_method :mobile_sort_by

  # Public: Returns the ID of the Repository being recommended, or nil.
  def repository_id
    # Might be called on an unfiltered RepositoryRecommendation, meaning the Repository could be
    # nil.
    repository.try(:id)
  end

  # Public: Opts this repository out of being recommended to anyone. Useful when the repository's
  # owner does not want their repository to get extra attention.
  #
  # Returns nothing.
  def opt_out(actor:)
    RepositoryRecommendationOptOut.connection.insert(Arel.sql(<<-SQL, repository_id: repository.id))
      INSERT INTO repository_recommendation_opt_outs (repository_id, created_at)
      VALUES (:repository_id, NOW())
      ON DUPLICATE KEY UPDATE repository_id = repository_id
    SQL

    repository.instrument_repository_recommendations_change(opt_out: true, actor: actor)
  end

  # Public: Restores the ability for this repository to be recommended to users. Useful when the
  # repository's owner changes their mind about opting their repository out.
  #
  # Returns a Boolean indicating success.
  def opt_in(actor:)
    opt_out = RepositoryRecommendationOptOut.where(repository_id: repository).first
    return true unless opt_out
    if opt_out.destroy
      repository.instrument_repository_recommendations_change(opt_out: false, actor: actor)
      true
    else
      false
    end
  end

  # Public: Returns repositories that are recommended for the given user.
  #
  # If Munger is down or unresponsive, trending repositories will be used instead.
  #
  # user - a User
  # page - which page of results to load; an Integer; defaults to 1
  # per_page - how many results to load; an Integer; defaults to 30
  #
  # Returns an Array of RepositoryRecommendations.
  def self.unfiltered_for(user, page: 1, per_page: Repository.per_page)
    return fallback_repositories_for(
      user,
      page: page,
      per_page: per_page,
    ) unless GitHub.munger_available?

    recommendations = fetch_munger_recommendations(
      user: user,
      page: page,
      per_page: per_page,
    )

    if Array(recommendations).size >= per_page
      recommendations
    elsif !recommendations.nil?
      fallback_recommendations = Array.wrap(fetch_munger_fallback_recommendations(
        user: user,
        page: page,
        per_page: per_page - recommendations.size,
      ))

      recommendations + fallback_recommendations
    else
      []
    end
  end

  def self.fetch_munger_fallback_recommendations(user:, page:, per_page:)
    GitHub.dogstats.time(time_key_for("fetch_munger_recommendations")) do
      GitHub.munger.repository_recommendations(
        user,
        page: page,
        per_page: per_page,
        fallback: true,
      )
    end
  end

  def self.fetch_munger_recommendations(user:, page:, per_page:)
    GitHub.dogstats.time(time_key_for("fetch_munger_recommendations")) do
      GitHub.munger.repository_recommendations(
        user,
        page: page,
        per_page: per_page,
      )
    end
  end

  # Public: Returns repositories that are recommended for the given user,
  # excluding repositories the user has already dismissed, spammy repositories,
  # private repositories, and recommendations for repositories that do not
  # exist.
  #
  # If Munger is down or unresponsive, trending repositories will be used instead.
  #
  # user - a User
  # page - which page of results to load; an Integer; defaults to 1
  # per_page - how many results to load; an Integer; defaults to 30
  #
  # Returns an Array of RepositoryRecommendation instances.
  #
  def self.filtered_for(user, page: 1, per_page: Repository.per_page)
    unfiltered = self.unfiltered_for(user, page: page, per_page: per_page)
    self.filter(unfiltered, user: user)
  end

  # Private: Returns a list of IDs for repositories that have been opted out of recommendations.
  #
  # Returns a subset of the given list of IDs, as an Array.
  def self.opted_out_repository_ids(repository_ids)
    GitHub.dogstats.time(time_key_for("fetch_opt_outs")) do
      filter_by_repository(repository_ids, scope: RepositoryRecommendationOptOut)
    end
  end
  private_class_method :opted_out_repository_ids

  # Private: Returns a list of IDs for repositories that are network restricted in that we want to
  # limit which users see them.
  #
  # Returns a subset of the given list of IDs, as an Array.
  def self.network_restricted_repository_ids(repository_ids)
    GitHub.dogstats.time(time_key_for("fetch_network_restricted_repos")) do
      scope = Stafftools::NetworkPrivilege.requires_login_or_collaborators_only
      filter_by_repository(repository_ids, scope: scope)
    end
  end
  private_class_method :network_restricted_repository_ids

  def self.hidden_from_discovery_repository_ids(repository_ids)
    scope = Stafftools::NetworkPrivilege.hidden_from_discovery
    filter_by_repository(repository_ids, scope: scope)
  end
  private_class_method :hidden_from_discovery_repository_ids

  # Private: Given a list of repository IDs and an ActiveRecord scope for a model that has a
  # `repository_id` field, this will return a subset of the given repository IDs that exist in
  # that scope.
  #
  # Returns an Array.
  def self.filter_by_repository(all_repository_ids, scope:)
    result = []
    all_repository_ids.each_slice(100) do |repository_ids|
      batch_result = scope.where(repository_id: repository_ids).pluck(:repository_id)
      result.concat(batch_result)
    end
    result
  end
  private_class_method :filter_by_repository

  # Private: Get unfiltered trending repositories for the given user.
  def self.fallback_repositories_for(user, page:, per_page:)
    # Fetch enough popular repositories to get the page we're on:
    limit = page * per_page

    # If you go beyond the last page of results, you get no results:
    return [] if limit > MAX_TRENDING_REPOS_TO_FETCH

    repos = popular_repositories(user, limit).map do |repository|
      new(repository: repository, reason: "trending")
    end

    offset = (page - 1) * per_page
    repos.drop(offset).take(per_page)
  end
  private_class_method :fallback_repositories_for

  # Private: Get the specified number of popular trending repositories.
  def self.popular_repositories(user, limit)
    GitHub.dogstats.time(time_key_for("fetch_popular_repositories")) do
      options = {
        language: nil,
        limit: limit,
        period: "daily",
        skip_min: GitHub.enterprise? || Rails.env.development? || Rails.env.test?,
      }
      cache_key = "trending:repos:query:daily:ids"
      repos_and_scores = Trending.repos(viewer: user, cache_key: cache_key, ttl: 3.hours, options: options)
      repos_and_scores.map(&:first)
    end
  end
  private_class_method :popular_repositories

  private

  # Private: Ignoring opt-outs, is this repo eligible to be recommended?
  def candidate_for_recommendation?
    # No Munger to provide recommendations in Enterprise.
    return false if GitHub.enterprise?

    # Only public, non-spammy, non-archived repositories can be recommended.
    !repository.private? && !repository.user_hidden? && !repository.archived? && !repository.async_is_hidden_from_discovery?.sync
  end
end
