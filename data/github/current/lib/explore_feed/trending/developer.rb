# typed: false
# frozen_string_literal: true

module ExploreFeed
  module Trending
    class Developer < SimpleDelegator
      include ExploreHelper

      DEFAULT_PERIOD = "daily"
      TRENDING_DEVELOPER_LIST_LIMIT = 25
      UNKNOWN_LANGUAGE_ID = "null"
      UNKNOWN_LANGUAGE_NAME = "unknown"

      attr_reader(
        :most_popular_repository,
        :original_user,
        :munger_profile_location,
        :score,
      )

      class << self
        def all(period: DEFAULT_PERIOD, language: nil, sponsorable: nil, limit: TRENDING_DEVELOPER_LIST_LIMIT)
          trending_developers_data = raw_trending_developers(
            language: language,
            period: period,
            sponsorable: sponsorable,
            limit: limit,
          )

          user_ids = trending_developers_data.map { |hash| hash["user_id"] }
          if sponsorable
            user_ids = SponsorsListing.with_approved_state.for_sponsorable_user_or_org(user_ids)
              .pluck(:sponsorable_id)
          end
          users_by_id = ::User.where(id: user_ids).index_by(&:id)

          repo_ids = trending_developers_data.map { |hash| hash["most_popular_repo_id"] }
          repos_by_id = ::Repository.public_scope.active.where(id: repo_ids).index_by(&:id)

          trending_developers = trending_developers_data.map do |hash|
            user_id = hash["user_id"]
            user = users_by_id[user_id]
            next unless user

            most_popular_repo_id = hash["most_popular_repo_id"]
            repo = repos_by_id[most_popular_repo_id]

            new(original_user: user, most_popular_repo: repo, **hash)
          end

          Collection
            .new(trending_developers.compact)
            .sorted
            .recommendable
        end

        private

        def raw_trending_developers(period:, language:, sponsorable:, limit:)
          GitHub.munger.trending_developers(
            language_id: language_id_for(language),
            page: 1,
            per_page: limit,
            period: period.to_sym,
            sponsorable: sponsorable,
          ) || []
        end

        def language_id_for(language_name)
          return if language_name.nil?
          return UNKNOWN_LANGUAGE_ID if language_name == UNKNOWN_LANGUAGE_NAME

          language = safe_find_linguist_language(language_name)
          linguist_id = language&.language_id
          LanguageName.find_by(linguist_id: linguist_id)&.id
        end

        def safe_find_linguist_language(language_name)
          deparameterized_language_name = language_name.split("-").join(" ")

          Linguist::Language.find_by_name(deparameterized_language_name) ||
            Linguist::Language.find_by_name(language_name) ||
            Linguist::Language.find_by_alias(language_name)
        end
      end

      def initialize(original_user:, most_popular_repo:, **attributes)
        @original_user = original_user
        @munger_profile_location = attributes["profile_location"]
        @score = attributes["score"]
        @most_popular_repository = most_popular_repo

        super(original_user)
      end

      def location_info_match?
        profile_location == munger_profile_location
      end

      class Collection
        include Enumerable

        def initialize(developers)
          @developers = developers
        end

        def each(&block)
          developers.each(&block)
        end

        def recommendable
          recommended_developers = developers
            .select(&:present?)
            .reject(&:spammy?)
            .reject(&:private_profile?)

          self.class.new(recommended_developers)
        end

        def sorted
          sorted_developers = developers
            .sort_by(&:score)
            .reverse
            .lazy

          self.class.new(sorted_developers)
        end

        def limit(limit)
          limited_developers = developers
            .first(limit)

          self.class.new(limited_developers)
        end

        private

        attr_accessor :developers
      end
    end
  end
end
