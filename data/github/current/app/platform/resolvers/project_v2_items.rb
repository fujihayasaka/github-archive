# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ProjectV2Items < Resolvers::Base
      type Connections.define(Objects::ProjectV2Item), null: false
      include GitHub::ResilienceMixin

      argument :include_archived, Boolean, "Include archived items.", default_value: true, required: false
      argument :allowed_owner, String, "Include items from an optional owner.", default_value: nil, required: false, visibility: :internal

      def resolve(**arguments)
        include_archived = arguments.fetch(:include_archived, true)
        allowed_owner = arguments.fetch(:allowed_owner, nil)

        target = object.kind_of?(::PullRequest) ? object.issue : object

        with_async_database_error_fallback(
          target.async_visible_memex_items_for(
            context[:viewer],
            include_archived: include_archived,
            allowed_owner: allowed_owner
          ).then do |items|
            ArrayWrapper.new(items)
          end,
          fallback: -> { raise Platform::Errors::ServiceUnavailable, "Project items are currently unavailable." }
        )
      end
    end
  end
end
