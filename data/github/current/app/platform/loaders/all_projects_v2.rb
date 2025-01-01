# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class AllProjectsV2 < Platform::Loader

      sig do
        params(
          user: User,
          viewer: User,
          query: String,
          min_permission_level: T.any(String, Symbol),
          use_full_term_query: T::Boolean
        ).returns(Promise[T::Array[MemexProject]])
      end
      def self.load(user, viewer, query, min_permission_level, use_full_term_query = false)
        self.for(user, viewer, min_permission_level, use_full_term_query).load(query)
      end

      sig { params(user: User, viewer: User, min_permission_level: T.any(String, Symbol), use_full_term_query: T::Boolean).void }
      def initialize(user, viewer, min_permission_level, use_full_term_query = false)
        @user = user
        @viewer = viewer
        @min_permission_level = min_permission_level
        @use_full_term_query = use_full_term_query
      end

      sig { params(query: T::Array[String]).returns(T::Hash[String, T::Array[MemexProject]]) }
      def fetch(query)
        @fetched_memex_projects ||= T.let({}, T.nilable(T::Hash[String, T::Array[MemexProject]]))

        query.each do |q|
          parsed_query = Search::Queries::MemexProjectQuery.new(q)

          if @fetched_memex_projects[q].nil?
            all_projects_result = user.all_projects_v2_for_user(
              query: parsed_query,
              viewer: viewer,
              min_permission_level: min_permission_level,
              use_full_term_query: use_full_term_query
            )

            @fetched_memex_projects[q] = all_projects_result.nil? ? [] : all_projects_result.memex_projects
          end
        end

        @fetched_memex_projects
      end

      private

      sig { returns(User) }
      attr_reader :user

      sig { returns(User) }
      attr_reader :viewer

      sig { returns(T.any(String, Symbol)) }
      attr_reader :min_permission_level

      sig { returns(T::Boolean) }
      attr_reader :use_full_term_query
    end
  end
end
