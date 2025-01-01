# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class IssueBlockedBy < Resolvers::Base
      include Platform::Helpers::DependenciesHelper

      argument :ranked, Boolean, "Sort issues in an order 'ranked' for the issue sidebar", required: false, default_value: false, visibility: :internal
      argument :order_by, Inputs::IssueDependencyOrder,
        "Ordering options for dependencies",
        required: false, default_value: { field: "dependency_added_at", direction: "DESC" }

      type Connections.define(Objects::Issue), null: false

      def resolve(**args)
        object.async_repository.then do |repository|
          return [] unless IssueDependenciesFeature.enabled?(repository, actor: context[:viewer])

          @object.async_filtered_blocked_by(viewer: context[:viewer], cap_filter: context[:cap_filter]).then do |blocked_by|
            blocked_by = rank_and_sort_issues(blocked_by, repository, args)
            ArrayWrapper.new(blocked_by)
          end
        end
      end
    end
  end
end
