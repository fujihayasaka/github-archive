# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ProjectV2Items < Resolvers::Base
      type Connections.define(Objects::ProjectV2Item), null: false
      include GitHub::ResilienceMixin

      argument :include_archived, Boolean, "Include archived items.", default_value: true, required: false
      argument :allowed_owner, String, "Include items from an optional owner.", default_value: nil, required: false, visibility: :internal
      argument :allow_same_enterprise, Boolean, "Allow items from the same enterprise.", default_value: false, required: false, visibility: :internal

      def resolve(**arguments)
        include_archived = arguments.fetch(:include_archived, true)
        allowed_owner = arguments.fetch(:allowed_owner, nil)
        allow_same_enterprise = arguments.fetch(:allow_same_enterprise, false)

        target = object.kind_of?(::PullRequest) ? object.issue : object

        # we only get repository and owner for the feature flag check, so remove these when we remove memex_allow_same_enterprise_items
        target.async_repository.then do |repository|
          repository.async_owner.then do |owner|
            allow_same_enterprise = false unless FeatureFlag.vexi.enabled?(:memex_allow_same_enterprise_items, [context[:viewer], owner], default: false)

            with_async_database_error_fallback(
              target.async_visible_memex_items_for(
                context[:viewer],
                include_archived: include_archived,
                allowed_owner: allowed_owner,
                allow_same_enterprise: allow_same_enterprise,
              ).then do |items|
                ArrayWrapper.new(items)
              end,
              fallback: -> { raise Platform::Errors::ServiceUnavailable, "Project items are currently unavailable." }
            )
          end
        end
      end
    end
  end
end
