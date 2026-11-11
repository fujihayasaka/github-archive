# typed: false
# frozen_string_literal: true

module Platform
  module Resolvers
    class StarredRepositories < Resolvers::Base
      # This matches https://github.com/rmosolgo/graphql-ruby/blob/1.9-dev/lib/graphql/schema/field/connection_extension.rb
      argument :after, "String", "Returns the elements in the list that come after the specified cursor.", required: false
      argument :before, "String", "Returns the elements in the list that come before the specified cursor.", required: false
      argument :first, "Int", "Returns the first _n_ elements from the list.", required: false
      argument :last, "Int", "Returns the last _n_ elements from the list.", required: false

      argument :owned_by_viewer, Boolean, "Filters starred repositories to only return repositories owned by the viewer.", required: false
      argument :order_by, Inputs::StarOrder, "Order for connection", required: false
      argument :repository_database_ids, [Integer, null: true],
        "Optional list of repository database IDs with which to filter the results. If provided, only starred repositories in this list will be returned.",
        visibility: :internal, required: false
      argument :language, String,
        "An optional programming language to use to filter the repositories.",
        visibility: :under_development, required: false
      argument :type, Enums::StarredRepositoryType,
        "An optional type to use to filter the repositories.",
        visibility: :under_development, required: false
      argument :query, String, "An optional filter to search the starred repositories.",
        required_capabilities: [:mobile_only_schema_mask], required: false

      type Connections::StarredRepository, null: true

      def resolve(query: nil, language: nil, order_by: nil, owned_by_viewer: nil,
                  repository_database_ids: nil, type: nil, user_session: nil, **connection_arguments)
        if @object.private_profile_for?(@context[:viewer])
          Platform::ConnectionWrappers::Relation.new(Repository.none)
        elsif query.present? || language.present?
          repo_query = search_starred_repositories(
            query: query,
            owned_by_viewer: owned_by_viewer,
            language: language,
            order_by: order_by,
            type: type,
            user_session: user_session,
          )

          Platform::ConnectionWrappers::SearchQuery.new(
            repo_query,
            first: connection_arguments[:first],
            last: connection_arguments[:last],
            after: connection_arguments[:after],
            before: connection_arguments[:before],
            arguments: connection_arguments,
            max_page_size: connection_arguments[:max_page_size],
            field: field,
            context: @context,
            parent: @object
          )
        else
          Platform::ConnectionWrappers::StarredRepositories.new(@object,
            field: field,
            context: @context,

            order_by: order_by,
            repository_database_ids: repository_database_ids,
            owned_by_viewer: owned_by_viewer,
            type: type,

            **connection_arguments
          )
        end
      end

      private

      def search_starred_repositories(query:, owned_by_viewer:, language:, order_by:, type:, user_session:)
        Search::Queries::RepoQuery.new(phrase: search_phrase(query, owned_by_viewer, type),
                                       source_fields: false,
                                       star_search: true,
                                       include_forks: true,
                                       current_user: context[:viewer],
                                       star_user: object,
                                       language: language,
                                       user_session: user_session,
                                       cap_filter: context[:cap_filter],
                                       sort: search_sort(order_by))
      end

      def search_phrase(query, owned_by_viewer, repo_type)
        phrase_parts = [query]

        # using the non-display version of login here is ok since this is being used in a query
        phrase_parts << "user:#{context[:viewer]}" if owned_by_viewer # rubocop:disable GitHub/DoNotAllowLogin

        repo_type_search_filter = search_filter_for_repo_type(repo_type)
        phrase_parts << repo_type_search_filter if repo_type_search_filter

        phrase_parts.compact.join(" ")
      end

      def search_filter_for_repo_type(repository_type)
        return if repository_type.blank?

        case repository_type
        when "public"      then "is:public archived:false"
        when "private"     then "is:private"
        when "fork"        then "fork:only archived:false"
        when "mirror"      then "mirror:true archived:false"
        when "template"    then "template:true archived:false"
        when "source"      then "mirror:false archived:false fork:false"
        when "sponsorable" then "is:sponsorable"
        end
      end

      def search_sort(order_by)
        return unless order_by

        direction = (order_by[:direction] || "desc").downcase
        case order_by[:field]
        when "pushed_at"
          ["updated", direction]
        when "watcher_count"
          ["stars", direction, "updated", direction]
        else
          # can't sort by "recently starred" while searching -- see #60971
          ["stars", direction]
        end
      end
    end
  end
end
