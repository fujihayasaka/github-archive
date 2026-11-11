# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class WatchingQuery

      LIMIT_MAX = 500

      attr_accessor :cursor, :cursor_direction, :limit, :viewer, :user
      attr_reader :model_to_be_queried

      def initialize(viewer, user)
        @viewer = viewer
        @user = user
        @model_to_be_queried = ::Repository
        @response = nil
      end

      def fetch!
        list_type = "Repository"
        lists_to_exclude = excluded_repo_ids.map do |id|
          ::Newsies::List.new(list_type, id)
        end

        @response = Notifications::Subscriptions.repository_subscriptions_by_cursor(
          user.id,
          excluding: lists_to_exclude,
          cursor: cursor,
          cursor_direction: cursor_direction,
          limit: calculate_limit,
        )

        if @response.failed?
          raise Platform::Errors::ServiceUnavailable.new("Watchers and watching features are currently unavailable. Please try again later.")
        end

        if @response.count >= LIMIT_MAX
          GitHub.logger.info("query result has reached max limit, user may experience inaccurate results", {
            "gh.viewer.id" => viewer.id,
            "gh.user.id" => user.id,
            "gh.notifications.list.type" => list_type,
            "gh.notifications.original_limit" => limit || ""
          })
        end

        @response.map(&:list_id)
      end

      def count
        fetch! unless @response
        @response.count
      end

      private

      def excluded_repo_ids
        repository_ids_to_hide = if viewer
          programmatic_accessible_repository_ids = ProgrammaticActor::RepositoryFilter.perform(
            # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
            actor: viewer, repository_ids: viewer.associated_repository_ids
            # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
          )

          # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          user.associated_repository_ids - programmatic_accessible_repository_ids
          # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
        else
          user.associated_repository_ids # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        end

        Repository.batched_scope(:id, values: repository_ids_to_hide) { |s| s.private_scope }.pluck(:id)
      end

      def calculate_limit
        return LIMIT_MAX if limit.nil?

        [limit, LIMIT_MAX].min
      end
    end
  end
end
