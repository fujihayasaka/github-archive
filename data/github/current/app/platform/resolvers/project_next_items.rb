# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ProjectNextItems < Resolvers::Base
      type Connections.define(Objects::ProjectNextItem), null: false

      argument :include_archived, Boolean, "Include archived items.", default_value: true, required: false

      def resolve(**arguments)
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(context[:viewer], context[:oauth_app])

        include_archived = arguments.fetch(:include_archived, true)

        target = object.kind_of?(::PullRequest) ? object.issue : object

        target.async_visible_memex_items_for(
          context[:viewer],
          include_archived: include_archived
        ).then do |items|
          ArrayWrapper.new(items)
        end
      end
    end
  end
end
