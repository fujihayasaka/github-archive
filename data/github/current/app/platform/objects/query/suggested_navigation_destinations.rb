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

      client_suggestions = page_views.slice(0, MAX_CLIENT_SUGGESTIONS).map do |page_key|
        Platform::Models::NavigationSuggestion.new(
          page_key: page_key,
        )
      end

      munger_suggestions = GitHub.munger.navigation_destinations(@context[:viewer]) || []
      munger_suggestions = munger_suggestions.map do |destination|
        Platform::Models::NavigationSuggestion.new(
          page_key: "#{destination.type.downcase}:#{destination.name}",
          last_visited_at: destination.last_visited_at,
          visit_count: destination.visit_count,
          generated_at: destination.generated_at,
        )
      end

      GitHub.dogstats.distribution("platform.query.suggested_navigation_destinations.munger_suggestions.count", munger_suggestions.size)

      suggestions = client_suggestions | munger_suggestions

      GitHub.dogstats.distribution("platform.query.suggested_navigation_destinations.total_suggestions.count", suggestions.size)

      # If munger is unavailable (i.e. Network error / GHE) use repositories contributed to.
      fallback_suggestions = []
      if munger_suggestions.empty?
        fallback_suggestions = @context[:viewer].repositories_contributed_to(
          viewer: @context[:viewer],
          limit: 20,
          exclude_owned: false,
          since: 15.days.ago,
        ).map { |repo| Platform::Models::NavigationSuggestion.new(destination: repo) }

        GitHub.dogstats.distribution("platform.query.suggested_navigation_destinations.fallback_suggestions.count", fallback_suggestions.size)
      end

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
        when /^project\:([^\/]+)\/([^\/]+)\/(\d*)$/
          owner_login = $1
          repo_name = $2
          project_number = $3.to_i
          Loaders::ActiveRecord.load(::User, owner_login, column: :login).then do |owner|
            next unless owner
            Loaders::RepositoryByName.load(owner.id, repo_name).then do |repo|
              next unless repo
              repo.async_projects_enabled?.then do |projects_enabled|
                next unless projects_enabled

                Loaders::ProjectByNumber.load(repo, project_number)
              end
            end
          end
        when /^project\:([^\/]+)\/([^\/]+)$/
          owner_login = $1
          project_number = $2.to_i
          Loaders::ActiveRecord.load(::Organization, owner_login, column: :login).then do |owner|
            next unless owner
            owner.async_projects_enabled?.then do |projects_enabled|
              next unless projects_enabled

              Loaders::ProjectByNumber.load(owner, project_number)
            end
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
          suggestions += fallback_suggestions
          ArrayWrapper.new(
            suggestions.compact.uniq { |suggestion| suggestion.destination.global_relay_id },
          )
        end
      end
    end
  end
end
