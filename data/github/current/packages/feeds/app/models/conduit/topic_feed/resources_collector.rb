# typed: true
# frozen_string_literal: true

module Conduit
  class TopicFeed::ResourcesCollector
    include ::GitHub::Memoizer

    TOP_REPO_KEY = :top_repository
    TRENDING_REPO_KEY = :trending_repository
    STARRED_REPO_KEY = :starred_repository
    TOP_CONTRIBUTOR_KEY = :top_contributor
    TRENDING_DEVELOPER_KEY = :trending_developer

    attr_reader :buckets

    def initialize(viewer:, topic:, config: nil, skip_cache: false)
      @viewer = viewer
      @topic = topic
      @config = config
      @skip_cache = skip_cache

      @buckets = {}
    end

    memoize def to_s
      return "" unless topic
      timer = Timer.start

      repositories.map { |repo| "#{repo.id}|repository" } +
        users.map { |user_id| "#{user_id}|user" }
    ensure
      GitHub.dogstats.distribution(
        "topic_feed_resource_collector.all",
        timer.elapsed_ms
      ) if timer
    end

    def empty?
      to_s.blank?
    end

    private

    memoize def repositories
      timer = Timer.start

      repos = []
      repos += top_topic_repos
      repos += top_language_repos
      repos += trending_repos
      repos += Array(official_repo)
      repos += starred_repos
      repos.uniq
    ensure
      GitHub.dogstats.distribution(
        "topic_feed_resource_collector.repositories",
        timer.elapsed_ms,
      )
    end

    memoize def users
      timer = Timer.start

      user_ids = []
      user_ids += top_contributors
      user_ids += trending_developers
      user_ids.uniq
    ensure
      GitHub.dogstats.distribution(
        "topic_feed_resource_collector.users",
        timer.elapsed_ms,
      )
    end

    sig { returns(T.nilable(Repository)) }
    def official_repo
      TopicFeed::Resources::OfficialRepo.new(
        viewer: viewer,
        topic: topic
      ).collect
    end

    sig { returns(T::Array[Repository]) }
    memoize def top_topic_repos
      repos = TopicFeed::Resources::TopRepos.new(
        viewer: viewer,
        topic: topic,
        skip_cache: skip_cache,
      ).collect
    ensure
      apply_bucket(repos, "repo", TOP_REPO_KEY)
    end

    sig { returns(T::Array[Repository]) }
    memoize def top_language_repos
      repos = TopicFeed::Resources::LanguageRepos.new(
        viewer: viewer,
        language: language,
      ).collect
    ensure
      apply_bucket(repos, "repo", TOP_REPO_KEY)
    end

    sig { returns(T::Array[Repository]) }
    memoize def trending_repos
      repos = TopicFeed::Resources::TrendingRepos.new(
        viewer: viewer,
        language: language,
      ).collect
    ensure
      apply_bucket(repos, "repo", TRENDING_REPO_KEY)
    end

    sig { returns(T::Array[Repository]) }
    memoize def starred_repos
      repos = TopicFeed::Resources::StarredRepos.new(
        viewer: viewer,
        topic: topic,
      ).collect
    ensure
      apply_bucket(repos, "repo", STARRED_REPO_KEY)
    end

    sig { returns(T::Array[Integer]) }
    memoize def top_contributors
      contributors = TopicFeed::Resources::TopContributors.new(
        viewer: viewer,
        repos: top_contributor_repos,
        topic: topic,
        skip_cache: skip_cache,
      ).collect
    ensure
      apply_bucket(contributors, "user", TOP_CONTRIBUTOR_KEY)
    end

    sig { returns(T::Array[User]) }
    memoize def trending_developers
      developers = TopicFeed::Resources::TrendingDevelopers.new(
        viewer: viewer,
        language: language,
      ).collect
    ensure
      apply_bucket(developers, "user", TRENDING_DEVELOPER_KEY)
    end

    memoize def top_contributor_repos
      top_topic_repos + top_language_repos + trending_repos
    end

    memoize def language
      LanguageName.find_by_alias(topic&.name)
    end

    sig { params(resources: T::Array[T.any(Integer, Repository)], key: String, label: Symbol).void }
    def apply_bucket(resources, key, label)
      resources.each do |resource|
        id = resource.is_a?(Integer) ? resource : resource.id
        @buckets["#{key}:#{id}"] = label
      end
    end

    attr_reader :viewer, :topic, :config, :skip_cache
  end
end
