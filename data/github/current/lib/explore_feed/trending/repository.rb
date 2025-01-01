# typed: false
# frozen_string_literal: true

module ExploreFeed
  module Trending
    class Repository < SimpleDelegator
      include ApplicationHelper
      include ActionView::Helpers::UrlHelper
      include ActionView::Context
      include AvatarHelper
      include ExploreHelper

      CACHE_TIME_FORMAT = "%Y-%m-%e"
      DEFAULT_PERIOD = "daily"
      LANGUAGE_NAME_CHARACTER_LIMIT = 25
      MINIMUM_SPOKEN_LANGUAGE_CONFIDENCE = 0.15
      TRENDING_REPOSITORY_LIST_LIMIT = 25
      UNKNOWN_LANGUAGE_ID = "null"
      UNKNOWN_LANGUAGE_NAME = "unknown"
      UNKNOWN_SPOKEN_LANGUAGE_CODE = "unknown"

      MINIMUM_REPO_AGE = 3.months
      MINIMUM_OWNER_AGE = 1.year
      MINIMUM_STAR_AGE = 2.weeks
      MINIMUM_CONTRIBUTOR_COUNT = 2
      MINIMUM_ISSUE_COUNT = 5
      MINIMUM_STAR_COUNT = 20
      MINIMUM_FORK_COUNT = 2
      MINIMUM_FOLLOWER_COUNT = 2

      attr_reader(
        :original_repository,
        :primary_language_id,
        :primary_language_name,
        :score,
        :spoken_language_code,
        :spoken_language_confidence,
      )

      def class
        self.repository.class
      end

      class << self
        def all(period: DEFAULT_PERIOD, language: nil, spoken_language_code: nil)
          trending_repos_data = raw_trending_repositories(
            language: language,
            period: period,
            spoken_language_code: spoken_language_code,
          ).uniq { |hash| hash["repository_id"] }

          repo_ids = trending_repos_data.map { |hash| hash["repository_id"] }
          repos_by_id = ::Repository
            .public_scope
            .active
            .includes(
              :network,           # used by #network_count
              :network_privilege, # used by #is_hidden_from_discovery?
              owner: [
                :trade_controls_restriction # used by #trade_restricted?
              ]
            )
            .where(id: repo_ids)
            .index_by(&:id)

          stars_by_repo_id = ::Star
            .where(starrable_id: repos_by_id.keys)
            .select("starrable_id, MIN(created_at) AS created_at")
            .group(:starrable_id)
            .index_by(&:starrable_id)

          trending_repos = trending_repos_data.map do |hash|
            repo_id = hash["repository_id"]
            repo = repos_by_id[repo_id]
            next unless repo
            new(original_repo: repo, preloaded_stars: stars_by_repo_id[repo_id], skip_min: Rails.env.test?, **hash)
          end

          Collection
            .new(trending_repos.compact)
            .sorted
            .by_spoken_language(spoken_language_code: spoken_language_code)
            .recommendable
        end

        private

        def raw_trending_repositories(period:, language:, spoken_language_code:)
          GitHub.munger.trending_repositories(
            language_id: language_id_for(language),
            page: 1,
            per_page: TRENDING_REPOSITORY_LIST_LIMIT,
            period: period.to_sym,
            spoken_language_code: spoken_language_query_param_for(spoken_language_code),
          ) || []
        end

        def language_id_for(language_name)
          return if language_name.nil?
          return UNKNOWN_LANGUAGE_ID if language_name == UNKNOWN_LANGUAGE_NAME

          linguist_language = safe_find_linguist_language(language_name)
          linguist_id = linguist_language&.language_id

          LanguageName.find_by(linguist_id: linguist_id)&.id
        end

        def safe_find_linguist_language(language_name)
          deparameterized_language_name = language_name.split("-").join(" ")

          Linguist::Language.find_by_name(deparameterized_language_name) ||
            Linguist::Language.find_by_name(language_name) ||
            Linguist::Language.find_by_alias(language_name)
        end

        def spoken_language_name_for(spoken_language_code)
          if spoken_language_code == UNKNOWN_SPOKEN_LANGUAGE_CODE
            "Unknown"
          else
            ::Trending::SpokenLanguageFinder
              .from_code(spoken_language_code)
              .name&.truncate(LANGUAGE_NAME_CHARACTER_LIMIT)
          end
        end

        def spoken_language_query_param_for(spoken_language_code)
          return if spoken_language_name_for(spoken_language_code).blank?

          if spoken_language_code == UNKNOWN_SPOKEN_LANGUAGE_CODE
            "null"
          else
            spoken_language_code
          end
        end
      end

      def initialize(original_repo:, preloaded_stars: nil, skip_min: false, **attributes)
        @original_repository = original_repo
        @primary_language_id = attributes["primary_language_id"]
        @primary_language_name = attributes["primary_language_name"]
        @score = attributes["score"]
        @spoken_language_code = attributes["spoken_language_code"]
        @spoken_language_confidence = attributes["spoken_language_confidence"]
        @preloaded_stars = Array(preloaded_stars)

        @min_contributor_count = skip_min ? 0 : MINIMUM_CONTRIBUTOR_COUNT
        @min_issue_count       = skip_min ? 0 : MINIMUM_ISSUE_COUNT
        @min_star_count        = skip_min ? 0 : MINIMUM_STAR_COUNT
        @min_fork_count        = skip_min ? 0 : MINIMUM_FORK_COUNT
        @min_follower_count    = skip_min ? 0 : MINIMUM_FOLLOWER_COUNT

        super(original_repo)
      end

      def present?
        original_repository.present?
      end

      def meets_spoken_language_confidence?
        spoken_language_confidence.to_f >= MINIMUM_SPOKEN_LANGUAGE_CONFIDENCE
      end

      def octicon_name
        if fork? && parent.present?
          "repo-forked"
        elsif mirror.present?
          if public?
            "mirror"
          else
            "lock"
          end
        else
          "repo"
        end
      end

      def total_stars
        score && score.fetch(:stars, {}).fetch(:total, nil)
      end

      def total_forks
        score && score.fetch(:forks, {}).fetch(:total, nil)
      end

      def description_html
        GitHub::Goomba::DescriptionPipeline.to_html(description)
      end

      def contributor_profile_links(force_cache_miss: nil)
        cache_key_time = DateTime.current.strftime(CACHE_TIME_FORMAT)
        cache_key = ["top_contributors", "repository", id, cache_key_time].join(".")

        GitHub.cache.fetch(cache_key, force: force_cache_miss) do
          users = original_repository.top_contributors(limit: 5, viewer: nil)

          users.map do |user, _|
            hydro_attributes = explore_click_tracking_attributes(
              click_context: :TRENDING_REPOSITORIES_PAGE,
              click_target: :CONTRIBUTING_DEVELOPER,
              click_visual_representation: :DEVELOPER_AVATAR,
            )

            profile_link(user, class: "d-inline-block", data: hydro_attributes) do
              avatar_for(user, 20, class:  "avatar mb-1")
            end
          end
        end
      end

      def meets_age_requirements?
        created_at <= MINIMUM_REPO_AGE.ago
      end

      def trusted_owner?
        return false unless present?

        async_owner.then do |owner|
          return false if owner.spammy?
          account_age_trusted? || owner_is_paid? || owner.hammy?
        end.sync
      end

      def low_engagement?
        contributor_count_or(0) < @min_contributor_count || open_issues_count < @min_issue_count
      end

      def trusted_following?
        minimum_stars? &&
        minimum_forks? &&
        owner_has_minimum_followers? &&
        starred_two_weeks_ago? &&
        stars_are_from_trusted_users?
      end

      def account_age_trusted?
        owner.created_at <= MINIMUM_OWNER_AGE.ago
      end

      def owner_is_paid?
        owner.paid_plan?
      end

      def minimum_stars?
        stargazer_count >= @min_star_count
      end

      def minimum_forks?
        forks_count >= @min_fork_count
      end

      def starred_two_weeks_ago?
        return true if @min_star_count == 0

        first_star = @preloaded_stars.first
        return false unless first_star.present?

        first_star.created_at <= MINIMUM_STAR_AGE.ago
      end

      def owner_has_minimum_followers?
        owner.followers_count(viewer: owner) >= @min_follower_count
      end

      def stars_are_from_trusted_users?
        return true if @min_star_count == 0
        @preloaded_stars.blank? ? false : true
      end

      class Collection
        include Enumerable

        def initialize(repositories)
          @repositories = repositories
        end

        def each(&block)
          repositories.each(&block)
        end

        def to_set
          Set.new(repositories)
        end

        def recommendable
          recommended_repositories = repositories
            .select(&:present?)
            .reject(&:private?)
            .reject(&:is_hidden_from_discovery?)
            .reject(&:trade_restricted?)
            .reject { |repo| repo.access.tos_violation? || repo.access.disabled_by_admin? || repo.access.disabled? }

          recommended_repositories = recommended_repositories
            .select(&:meets_age_requirements?)
            .select(&:trusted_owner?)
            .select(&:trusted_following?)
            .reject(&:low_engagement?)

          self.class.new(recommended_repositories)
        end

        def by_spoken_language(spoken_language_code:)
          trending_repositories = if spoken_language_code.present?
            repositories.select(&:meets_spoken_language_confidence?)
          else
            repositories
          end

          self.class.new(trending_repositories)
        end

        def sorted
          sorted_repositories = repositories
            .sort_by(&:score)
            .reverse
            .lazy

          self.class.new(sorted_repositories)
        end

        # Sorts by mobile sorting order:
        #  1. Has a custom image
        #  2. Belongs to an organization
        #  3. All other repositories
        def sorted_for_mobile
          sorted_repositories = repositories
            .sort_by { |repo| mobile_sort_by(repo) }
            .reverse
            .lazy

          self.class.new(sorted_repositories)
        end

        def limit(limit)
          limited_repositories = repositories
            .first(limit)

          self.class.new(limited_repositories)
        end

        def next_two(starting_point: 0)
          next_two_repositories = repositories
            .to_a[starting_point, 2]

          self.class.new(next_two_repositories || [])
        end

        def rest(starting_point: 0)
          rest_of_the_repositories = repositories
            .to_a[starting_point..-1]

          self.class.new(rest_of_the_repositories || [])
        end

        private

        attr_accessor :repositories

        def mobile_sort_by(repo)
          uses_custom_image = repo.async_uses_custom_open_graph_image?.sync ? 1 : 0
          in_organization = repo.in_organization? ? 1 : 0

          [uses_custom_image, in_organization]
        end
      end
    end
  end
end
