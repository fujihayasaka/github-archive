# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::SuggestedNavigationDestinations
  extend ActiveSupport::Concern
  extend T::Helpers
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames
  requires_ancestor { Platform::Objects::Query }

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))

    field :suggested_navigation_destinations, Connections::NavigationDestination,
      description: "A list of suggested navigation destinations for the viewer.",
      visibility: :internal,
      null: false,
      connection: true do

      argument :page_views, [String], "Sorted list of recent page views. Each page should follow the following pattern `type:path`", required: false
    end

    # Restrict the number of suggestions to prevent abuse.
    MAX_CLIENT_SUGGESTIONS = 100

    def suggested_navigation_destinations(page_views: [])
      return ArrayWrapper.new([]) unless @context[:viewer]

      GitHub.dogstats.distribution("platform.query.suggested_navigation_destinations.page_views.count", page_views.size)

      suggestions = page_views.slice(0, MAX_CLIENT_SUGGESTIONS).map do |page_key|
        Platform::Models::NavigationSuggestion.new(
          page_key: page_key,
        )
      end
      GitHub.dogstats.distribution("platform.query.suggested_navigation_destinations.total_suggestions.count", suggestions.size)

      contributed_to_suggestions = @context[:viewer].repositories_contributed_to(
        viewer: @context[:viewer],
        limit: 20,
        exclude_owned: false,
        since: 15.days.ago,
      ).map { |repo| Platform::Models::NavigationSuggestion.new(destination: repo) }
      GitHub.dogstats.distribution("platform.query.suggested_navigation_destinations.contributed_to_suggestions.count", contributed_to_suggestions.size)

      promises = suggestions.map do |page_view|

        promise = case page_view.page_key
        when /^repository\:([^\/]+)\/([^\/]+)$/
          owner_login = $1
          repo_name = $2
          Loaders::ActiveRecord.load(::User, owner_login, column: :login).then do |owner|
            next unless owner
            Loaders::RepositoryByName.load(owner.id, repo_name)
          end
        when /^team\:([a-z0-9-]+)\/([\w-]+)/
          org_login = $1
          team_slug = $2
          Loaders::ActiveRecord.load(::Organization, org_login, column: :login).then do |org|
            next unless org
            Loaders::TeamBySlug.load(org, team_slug)
          end
        end

        next promise
      end

      Promise.all(promises).then do |objects|
        objects.zip(suggestions).map do |object, page_view|
          next unless object
          type_name = Helpers::NodeIdentification.type_name_from_object(object)
          context[:permission].typed_can_see?(type_name, object).then do |can_read|
            next unless can_read
            page_view.destination = object
            page_view
          end
        end
      end.then do |promises|
        Promise.all(promises).then do |suggestions|
          suggestions += contributed_to_suggestions
          ArrayWrapper.new(
            suggestions.compact.uniq { |suggestion| suggestion.destination.global_relay_id },
          )
        end
      end
    end
  end
end
