# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    module DependenciesHelper
      sig do
        params(
          issues: T::Array[Issue],
          repository: Repository,
          args: T::Hash[Symbol, T.untyped]
        ).returns(T::Array[Issue])
      end
      def rank_and_sort_issues(issues, repository, args)
        case args.dig(:order_by, :field)
        when "created_at"
          issues.sort_by!(&:created_at)
        when "dependency_added_at"
          # this is the default order when querying dependencies
        end
        issues.reverse! if args.dig(:order_by, :direction) == "DESC"
        issues.sort_by! do |issue|
          [
            issue.open? ? 0 : 1,
            issue.repository_id == repository.id ? 0 : 1,
            issue.repository&.owner_id == repository.owner_id ? 0 : 1
          ]
        end if args[:ranked]
        issues
      end
    end
  end
end
