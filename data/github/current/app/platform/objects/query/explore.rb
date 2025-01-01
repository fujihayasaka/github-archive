# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform::Objects::Query::Explore
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    field :collection, Objects::ExploreCollection, description: "Lookup a collection by slug.", null: true do
      argument :slug, String, "The collection's slug.", required: true
    end

    def collection(**arguments)
      Loaders::ActiveRecord.load(::ExploreCollection, arguments[:slug], column: :slug).then do |collection|
        if collection
          collection
        else
          raise Platform::Errors::NotFound, "Could not resolve to a Collection with the slug of '#{arguments[:slug]}'."
        end
      end
    end

    field :topic, Objects::Topic, description: "Look up a topic by name.", null: true do
      argument :name, String, "The topic's name.", required: true
    end

    def topic(**arguments)
      Objects::Topic.load_from_global_id(arguments[:name])
    end

    field :popular_topics, [Objects::Topic], visibility: :internal, description: "Returns a list of popular topics featured on GitHub.", null: false do
      argument :limit, Integer, "How many popular topics to return.", default_value: 10, required: false
    end

    def popular_topics(**arguments)
      ::Topic.not_flagged.popular_on_public_repositories(arguments[:limit])
    end

    field :recent_topics, [Objects::Topic], visibility: :internal, description: <<~DESCRIPTION, null: false do
        Returns a list of recently created topics on GitHub that have been applied to at least
        one repository.
      DESCRIPTION

      argument :limit, Integer, "How many recent topics to return.", default_value: 10, required: false
    end

    def recent_topics(**arguments)
      topic_ids = ::RepositoryTopic.applied.on_public_repositories.newest_first.limit(100).
        pluck(:topic_id)
      ::Topic.newest_first.not_flagged.where(id: topic_ids).limit(arguments[:limit])
    end

    field :applied_topics, [Objects::Topic], visibility: :internal, description: "Returns a list of applied topics filtered by `query` if any.", null: false do
      argument :query, String, "Query to search applied topics by", required: false
      argument :limit, Integer, "How many applied topics to return.", default_value: 10, required: false
    end

    def applied_topics(**arguments)
      ::Topic.suggestions_for_autocomplete(query: arguments[:query], limit: arguments[:limit])
    end

    field :featured_topics_sample, [Objects::Topic], visibility: :internal, description: "Returns a few randomly chosen featured, curated topics.", null: false do
      argument :limit, Integer, "How many topics to return.", default_value: 3, required: false
    end

    def featured_topics_sample(**arguments)
      topics = ::Topic.not_flagged.curated.featured.with_logo.newest_first.limit(1_000).
        sample(arguments[:limit])
      ArrayWrapper.new(topics.shuffle)
    end


    field :topics, Connections.define(Objects::Topic), visibility: :internal, description: "Returns a list of the topics on GitHub.", null: false, connection: true do
      argument :featured, Boolean, "Set to true to include only the topics featured on GitHub.", required: false
      argument :curated, Boolean, "Set to true to include only the topics that have additional content, such as a " \
        "description.", default_value: false, required: false
      argument :query, String, "A query for filtering topics by name.", required: false
      argument :order_by, Inputs::TopicOrder, "Ordering options for the returned topics.", required: false
      argument :names, [String, null: true], "A list of topic names to include.", required: false
    end

    def topics(**arguments)
      topics = ::Topic.not_flagged
      topics = topics.curated if arguments[:curated]

      if arguments[:names].present?
        names = arguments[:names].select { |name| Topic.valid_name?(name) }
        topics = topics.where(name: names)
      end

      if arguments[:featured]
        topics = topics.featured
      elsif arguments[:featured] == false # as opposed to nil
        topics = topics.non_featured
      end

      if arguments[:query].present?
        topics = topics.with_name_like(arguments[:query])
      end

      if arguments[:order_by]
        field = arguments[:order_by][:field]
        direction = arguments[:order_by][:direction]
        topics = topics.order("topics.#{field} #{direction}")
      end

      topics
    end

    # TODO Before going public, fix `display_names` -> `displayNames` (remove `camelize: false`)
    field :explore_collections, Connections.define(Objects::ExploreCollection), visibility: :internal, description: "Returns a list of the collections on GitHub Explore.", null: false, connection: true do
      argument :featured, Boolean, "Set to true to include only the collections featured on GitHub.", required: false
      argument :query, String, "A query for filtering collections by name.", required: false
      argument :order_by, Inputs::ExploreCollectionOrder, "Ordering options for the returned collections.", required: false
      argument :slugs, [String, null: true], "A list of collection slugs to include.", required: false
      argument :display_names, [String, null: true], "A list of collection names to include.", required: false, camelize: false
    end

    def explore_collections(**arguments)
      collections = ::ExploreCollection.limit(1_000)

      if arguments[:slugs].present?
        slugs = arguments[:slugs].select { |slug| ::ExploreCollection.valid_slug?(slug) }
        collections = collections.where(slug: slugs)
      end

      if arguments[:display_names].present?
        display_names = arguments[:display_names].select { |name| ::ExploreCollection.valid_name?(name) }
        collections = collections.where(display_name: display_names)
      end

      if arguments[:featured]
        collections = collections.featured
      elsif arguments[:featured] == false # as opposed to nil
        collections = collections.non_featured
      end

      if arguments[:query].present?
        collections = collections.with_name_like(arguments[:query])
      end

      if arguments[:order_by]
        field = arguments[:order_by][:field]
        direction = arguments[:order_by][:direction]
        collections = collections.order("collections.#{field} #{direction}")
      end

      collections
    end

    field :featured_collections_sample, [Objects::ExploreCollection], visibility: :internal, description: "Returns a few randomly chosen featured, curated collections.", null: false do
      argument :limit, Integer, "How many collections to return.", default_value: 3, required: false
    end

    def featured_collections_sample(**arguments)
      collections = ::ExploreCollection.featured.limit(1_000).
        sample(arguments[:limit])
      ArrayWrapper.new(collections.shuffle)
    end

    field :trending_developers, [Objects::User, null: true], mobile_only: true, description: "A list of trending developers", null: true

    def trending_developers
      ExploreFeed::Trending::Developer.all
    end

    field :trending_repositories, [Objects::Repository, null: true], mobile_only: true, description: "A list of trending repositories", null: true do
      argument :language, String, "The programming language to filter repositories by.", required: false, default_value: nil
      argument :period, Enums::TrendingPeriod, "Limit repositories returned to those that were trending in this time period.", required: false, default_value: :daily
      argument :spoken_language_code, String, "Filter repositories by spoken language using a two-character language code such as 'en' for English.", required: false, default_value: nil
      argument :mobile_sort_order, Boolean, "List repositories with the mobile sort order.", required: false, default_value: false, mobile_only: true
    end

    def trending_repositories(**arguments)
      results = ExploreFeed::Trending::Repository.all(
        period: arguments[:period] || :daily,
        language: arguments[:language],
        spoken_language_code: arguments[:spoken_language_code]
      )

      results = results.sorted_for_mobile if arguments[:mobile_sort_order]

      results.map(&:original_repository)
    end

    field :spoken_languages, [Objects::SpokenLanguage, null: true], mobile_only: true, description: "A list of spoken languages", null: false do
      argument :name, String, "Name of a spoken language to find.", required: false
    end

    def spoken_languages(**arguments)
      if arguments[:name]
        Trending::SpokenLanguageFinder.from_name(arguments[:name])
      else
        Trending::SpokenLanguageFinder.all
      end
    end

    field :programming_languages, [Objects::Language, null: true], mobile_only: true, description: "A list of programming languages", null: false do
      argument :suggested, Boolean, "Display the user's suggested programming languages at the top of the list.", required: false, default_value: false
      argument :name, String, "Name of a programming language to find.", required: false
    end

    def programming_languages(**arguments)
      not_all_languages = arguments[:suggested] && @context[:viewer].any_starred_repositories?

      if not_all_languages
        keys = @context[:viewer].starred_repositories_by_language(language_limit: 7, apply_star_limit: false).keys.sort

        top_languages = LanguageName.lookup_by_names(keys)
        other_languages = LanguageName.all_sorted - top_languages

        result = top_languages + other_languages
      else
        result = LanguageName.all_sorted
      end

      if arguments[:name]
        query = arguments[:name].downcase.strip
        result.each_with_object([]) do |lang, sorted|
          if lang.name.downcase == query
            sorted.prepend(lang)
          elsif lang.name.downcase.include?(query)
            sorted.append(lang)
          end
        end
      else
        result
      end
    end
  end
end
