# typed: strict
# frozen_string_literal: true

module IssuesDashboardSurface
  module Payloads
    class SearchResultsDeferredContent
      class SubIssuesSummary < T::Struct
        const :total, Integer
        const :completed, Integer
        const :percentCompleted, Integer
      end

      class ReactionGroupResult < T::Struct
        const :content, String
        const :totalCount, Integer
      end

      class IssueDeferredResult < T::Struct
        const :id, Integer
        const :itemType, String
        const :isReadByCurrentUser, T::Boolean
        const :linkedPullRequestCount, Integer
        const :subIssuesSummary, SubIssuesSummary
        const :blockedByCount, Integer
        const :reactionGroups, T.nilable(T::Array[ReactionGroupResult])
      end

      sig { params(results: IssuesDashboardSurface::ResultsLoader::DeferredData).void }
      def initialize(results)
        @results = results
      end

      sig { params(results: IssuesDashboardSurface::ResultsLoader::DeferredData).returns(T.untyped) }
      def self.serialize(results)
        new(results).serialize
      end

      sig { returns({ results: T::Array[IssueDeferredResult] }) }
      def serialize
        {
          results: @results.issues.map do |issue|
            sub_issue_list = issue.sub_issue_list
            sub_issues = if sub_issue_list
              SubIssuesSummary.new(
                total: sub_issue_list.total,
                completed: sub_issue_list.completed,
                percentCompleted: sub_issue_list.percent_completed,
              )
            else
              SubIssuesSummary.new(total: 0, completed: 0, percentCompleted: 0)
            end

            dependency_list = issue.issue_dependency_list
            blocked_by_count = dependency_list ? dependency_list.blocked_by : 0

            IssueDeferredResult.new(
              id: issue.id,
              itemType: "issue",
              isReadByCurrentUser: @results.read_issue_ids.include?(issue.id),
              linkedPullRequestCount: @results.linked_pull_request_counts[issue.id] || 0,
              subIssuesSummary: sub_issues,
              blockedByCount: blocked_by_count,
              reactionGroups: serialize_reaction_groups(issue.id),
            )
          end,
        }
      end

      sig { params(issue_id: Integer).returns(T.nilable(T::Array[ReactionGroupResult])) }
      private def serialize_reaction_groups(issue_id)
        groups_by_issue = @results.reaction_groups
        return nil unless groups_by_issue

        groups = groups_by_issue[issue_id]
        return nil unless groups

        groups.filter_map do |group|
          next if group.total_count == 0

          ReactionGroupResult.new(
            content: group.content,
            totalCount: group.total_count,
          )
        end
      end
    end
  end
end
