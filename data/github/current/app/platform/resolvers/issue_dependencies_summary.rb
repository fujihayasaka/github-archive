# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class IssueDependenciesSummary < Platform::Resolvers::Base
      type Objects::IssueDependenciesSummary, null: false

      def resolve
        object.async_repository.then do |repository|
          next IssueDependencyList::Summary.empty unless IssueDependenciesFeature.enabled?(repository, actor: context[:viewer])

          object.async_issue_dependencies_summary(calculate: should_recalculate_issue_dependencies_summary?).then do |summary| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            summary
          end
        end
      end

      # Returns whether or not we should recalculate the issue dependencies summary and not use the denormalized values,
      # based on the mutation name in the context. This is used to determine if we should recalculate the summary
      # when adding or removing blocked by relationships so we can return the updated summary immediately.
      sig { returns(T::Boolean) }
      private def should_recalculate_issue_dependencies_summary?
        context[:mutation_name] == "add_blocked_by" || context[:mutation_name] == "remove_blocked_by"
      end
    end
  end
end
