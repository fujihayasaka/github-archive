# typed: true
# frozen_string_literal: true

module PullRequests::PageData::MergeBox
  class MergeRequirementsPayload
    class MergeConditionResult < T::Enum
      enums do
        Passed = new("PASSED")
        Failed = new("FAILED")
        Unknown = new("UNKNOWN")
      end
    end

    class MergeConditionType < T::Enum
      enums do
        PullRequestState = new("PULL_REQUEST_STATE")
        PullRequestRepoState = new("PULL_REQUEST_REPO_STATE")
        PullRequestUserState = new("PULL_REQUEST_USER_STATE")
        PullRequestRules = new("PULL_REQUEST_RULES")
        PullRequestMergeConflictState = new("PULL_REQUEST_MERGE_CONFLICT_STATE")
        PullRequestMergeMethod = new("PULL_REQUEST_MERGE_METHOD")
        Unknown = new("UNKNOWN")
      end
    end

    class MergeConditionPayload < T::Struct
      const :type, MergeConditionType
      const :displayName, String
      const :description, String
      const :message, T.nilable(String)
      const :result, MergeConditionResult
      prop :ruleRollups, T.nilable(T::Array[RulesEngine::RepositoryRuleRollup::RuleRollupPayload])
    end

    class ConflictMergeConditionPayload < T::Struct
      const :type, MergeConditionType
      const :displayName, String
      const :description, String
      const :message, T.nilable(String)
      const :result, MergeConditionResult
      prop :ruleRollups, T.nilable(T::Array[RulesEngine::RepositoryRuleRollup::RuleRollupPayload])
      const :conflicts, T.nilable(T::Array[String])
      const :isConflictResolvableInWeb, T.nilable(T::Boolean)
    end

    class MergeRequirementsState < T::Enum
      enums do
        Mergeable = new("MERGEABLE")
        Unknown = new("UNKNOWN")
        Unmergeable = new("UNMERGEABLE")
        MergeableIfStatusesPass = new("MERGEABLE_IF_STATUSES_PASS")
      end
    end

    class MergeRequirementsPayload < T::Struct
      const :state, MergeRequirementsState
      const :conditions, T::Array[T.any(MergeConditionPayload, ConflictMergeConditionPayload)]
      const :commitAuthorEmail, String
      const :commitMessageHeadline, T.nilable(String)
      const :commitMessageBody, T.nilable(String)
    end

    sig do
      params(
        merge_requirements_data: T.untyped
      ).returns(MergeRequirementsPayload)
    end
    def self.call(merge_requirements_data)
      new.call(merge_requirements_data)
    end

    sig { params(merge_requirements_data: T.untyped).returns(MergeRequirementsPayload) }
    def call(merge_requirements_data)
      MergeRequirementsPayload.new(
        state: MergeRequirementsState.deserialize(merge_requirements_data.state.upcase.to_s),
        conditions: merge_requirements_data.conditions,
        commitAuthorEmail: merge_requirements_data.commit_author_email,
        commitMessageHeadline: merge_requirements_data.commit_message_headline,
        commitMessageBody: merge_requirements_data.commit_message_body,
      )
    end
  end
end
