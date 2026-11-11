# typed: strict
# frozen_string_literal: true

module IssuesDashboardSurface
  class ResultsLoader
    class ReactionGroupData < T::Struct
      const :content, String
      const :total_count, Integer
    end

    class DeferredData < T::Struct
      const :issues, T::Array[Issue]
      const :linked_pull_request_counts, T::Hash[Integer, Integer]
      const :read_issue_ids, T::Set[Integer]
      const :reaction_groups, T.nilable(T::Hash[Integer, T::Array[ReactionGroupData]])
    end

    sig { params(issues: T::Array[Issue], current_user: T.nilable(User)).returns(T::Array[Issue]) }
    def self.main_content_from(issues:, current_user:)
      # Filter out any pull request issues that may have leaked through
      plain_issues = issues.reject(&:pull_request?)

      if current_user
        read_issues = Issue.read_for(current_user, plain_issues)
        plain_issues.each do |issue|
          issue.read_by_current_user = read_issues.include?(issue.id)
        end
      end

      IssuePrefiller.prefill(plain_issues, current_user: current_user)
      plain_issues
    end

    sig { params(issues: T::Array[Issue], current_user: T.nilable(User), cap_filter: ConditionalAccess::Filter, include_reactions: T::Boolean).returns(DeferredData) }
    def self.deferred_content_from(issues:, current_user:, cap_filter:, include_reactions: false)
      plain_issues = issues.reject(&:pull_request?)

      GitHub::PrefillAssociations.prefill_batch_method(plain_issues, :repository)
      IssuePrefiller.prefill(plain_issues, only_prefill: [:sub_issue_list, :close_issue_references], current_user: current_user)

      linked_pr_counts = load_linked_pull_request_counts_for(plain_issues, current_user, cap_filter)
      read_issue_ids = current_user ? Issue.read_for(current_user, plain_issues) : Set.new
      GitHub::PrefillAssociations.prefill_associations(plain_issues, [:issue_dependency_list])

      reaction_groups = if include_reactions && plain_issues.any?
        extract_reaction_groups(plain_issues)
      end

      DeferredData.new(
        issues: plain_issues,
        linked_pull_request_counts: linked_pr_counts,
        read_issue_ids: read_issue_ids,
        reaction_groups: reaction_groups,
      )
    end

    sig { params(issues: T::Array[Issue], current_user: T.nilable(User), cap_filter: ConditionalAccess::Filter).returns(T::Hash[Integer, Integer]) }
    private_class_method def self.load_linked_pull_request_counts_for(issues, current_user, cap_filter)
      return {} if issues.empty?

      promises = issues.map do |issue|
        issue.async_cap_filtered_closed_by_pull_requests_references_for(
          viewer: current_user,
          cap_filter: cap_filter,
        ).then { |pulls| [issue.id, pulls.size] }
      end

      Promise.all(promises).sync.to_h
    end

    sig { params(issues: T::Array[Issue]).returns(T::Hash[Integer, T::Array[ReactionGroupData]]) }
    private_class_method def self.extract_reaction_groups(issues)
      raw_groups = Platform::Loaders::ReactionGroups.new("Issue").fetch(issues)
      raw_groups.each_with_object({}) do |(issue, groups), result|
        result[issue.id] = groups.map do |group|
          ReactionGroupData.new(
            content: group.emotion.platform_enum,
            total_count: group.total_count,
          )
        end
      end
    end
  end
end
