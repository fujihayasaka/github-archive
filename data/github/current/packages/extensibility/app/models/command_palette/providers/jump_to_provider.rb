# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    class JumpToProvider < ApplicationProvider
      # Match on string starting with `<owner>/`
      STARTS_WITH_OWNER = %r[\A(?<owner>[^/]+)/(?<everything_else>.*)]

      def self.modes
        [:global_jump_to, :owner_jump_to]
      end

      def search(query)
        return [] unless scope_matches?
        return [] if query.blank?

        objects = search_for_owners(query)
        objects += search_for_repositories(query)
        objects.uniq.map do |object|
          Result.jump_to(object, context: context)
        end
      end

      delegate :repository, :owner, to: :scope
      def build_query_helper(query)
        Search::QueryHelper.new(
          query,
          nil,
          current_user: current_user,
          per_page: 10,
          user_session: context.user_session,
          cap_filter: context.cap_filter,
        )
      end

      def search_for_owners(query)
        return [] if scope.owner

        build_query_helper(query)
          .user_query
          .execute
          .results
          .map(&:user)
      end

      def search_for_repositories(query)
        search_es_for_repositories(query) + search_by_nwo(query)
      end

      def search_es_for_repositories(query)
        scoped_query =
          if scope.owner
            "#{query} user:#{scope.owner.login}"
          elsif (match = query.match(STARTS_WITH_OWNER))
            "#{match[:everything_else]} user:#{match[:owner]}"
          else
            query
          end

        build_query_helper(scoped_query)
          .command_palette_repo_query
          .execute
          .results
          .map(&:repo)
      end

      def search_by_nwo(query)
        match = query.match(STARTS_WITH_OWNER)

        return [] if match.nil?
        return [] if scope.repository

        owner_login = match[:owner]
        repo_name = match[:everything_else]

        owner = User.find_by(login: owner_login)
        return [] if owner.nil?

        outside_scope = scope.owner && scope.owner != owner
        return [] if outside_scope

        repository = owner.repositories.find_by(name: repo_name)
        if repository&.readable_by?(current_user)
          [repository]
        else
          []
        end
      end
    end
  end
end
