# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ProjectV2ByQuery < Platform::Loader
      extend T::Sig

      sig do
        params(
          object: T.any(::User, ::Organization, ::Issue, ::PullRequest, ::Team, ::Repository),
          viewer: ::User,
          query: String,
          min_permission_level: String,
          use_full_term_query: T::Boolean
        ).returns(Promise[T::Array[::MemexProject]])
      end
      def self.load(object, viewer, query, min_permission_level = "read", use_full_term_query = false)
        self.for(object, viewer, min_permission_level, use_full_term_query).load(query)
      end

      sig do
        params(
          object: T.any(::User, ::Organization, ::Issue, ::PullRequest, ::Team, ::Repository),
          viewer: ::User,
          min_permission_level: String,
          use_full_term_query: T::Boolean
        ).void
      end
      def initialize(object, viewer, min_permission_level = "read", use_full_term_query = false)
        @object = object
        @viewer = viewer
        @min_permission_level = min_permission_level
        @use_full_term_query = use_full_term_query
      end

      sig do
        params(
          queries: T::Array[String]
        ).returns(
          Promise[T::Hash[String, T::Array[::MemexProject]]]
        )
      end
      def fetch(queries)
        filter_ids = T.let([], T::Array[Integer])
        parsed_queries = Hash.new
        results = Hash.new

        queries.map do |query|
          parsed_query = query.blank? ? nil : Search::Queries::MemexProjectQuery.new(query)
          parsed_queries[query.blank? ? "" : query] = parsed_query
        end

        memexes_promise = case @object
        when ::Issue, ::PullRequest
          source = T.must(T.must(@object.repository).owner)
          source.async_accessible_memexes_scope(
            MemexProject.where(
              id: source.memex_projects.pluck(:id)
            ),
            @viewer,
            @min_permission_level
          )
        when ::Repository
          source = @object
          filter_ids = @object.memex_projects.pluck(:id)
          @object.async_memex_projects_scope_for(
            @viewer,
            @min_permission_level,
            filter_ids: filter_ids
          )
        when ::Team
          source = T.must(@object.organization)
          ::Platform::Loaders::MemexProjectUserRoleByActorAndProject.load(
            actor_id: @object.id,
            actor_type: ::Platform::Loaders::MemexProjectUserRoleByActorAndProject::ActorType::Team
          ).then do |user_roles|
            filter_ids = user_roles.map(&:target_id)
            source.async_accessible_memexes_scope(
                MemexProject.where(id: filter_ids),
                @viewer,
                @min_permission_level,
                filter_ids: filter_ids
              )
          end
        when ::User, ::Organization
          source = @object.owner
          source.async_accessible_memexes_scope(
            MemexProject.where(
              id: source.memex_projects.pluck(:id)
            ),
            @viewer,
            @min_permission_level
          )
        end

        Promise.resolve(memexes_promise).then do |memexes|
          parsed_queries.each do |query, parsed_query|
            if query.blank?
              results[query] = memexes
            else
              results[query] = T.must(source).search_memex_projects(
                query: parsed_query,
                viewer: @viewer,
                limit: nil,
                filter_ids: filter_ids,
                min_permission_level: @min_permission_level,
                use_full_term_query: @use_full_term_query
              ).memex_projects
            end
          end

          results
        end
      end
    end
  end
end
