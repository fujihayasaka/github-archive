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

    class CannotResolveConflictsReason < T::Enum
      enums do
        InsufficientAccess = new("INSUFFICIENT_ACCESS")
        TooComplex = new("TOO_COMPLEX")
        HeadBranchProtected = new("HEAD_BRANCH_PROTECTED")
        AdminDisabled = new("ADMIN_DISABLED")
      end
    end

    class FailingSubConditionPayload < T::Struct
      const :displayName, String
      prop :message, T.nilable(String)
    end

    # Generic Merge Condition (does not provide visibility into underlying failures)
    class GenericMergeConditionPayload < T::Struct
      const :type, MergeConditionType
      const :displayName, String
      const :description, String
      prop :message, T.nilable(String)
      const :result, MergeConditionResult
    end

    # Rules Engine
    class RepositoryRulesMergeConditionPayload < T::Struct
      const :type, MergeConditionType
      const :displayName, String
      const :description, String
      prop :message, T.nilable(String)
      const :result, MergeConditionResult
      prop :ruleRollups, T.nilable(T::Array[RulesEngine::RepositoryRuleRollup::RuleRollupPayload])
    end

    class ViewerCannotResolve < T::Struct
      const :reason, CannotResolveConflictsReason
      const :message, String
    end

    class MergeConflictWebEditorResolution < T::Struct
      const :viewerCanResolve, T::Boolean
      const :viewerCannotResolve, T.nilable(ViewerCannotResolve)
    end

    # Conflict
    class ConflictMergeConditionPayload < T::Struct
      const :type, MergeConditionType
      const :displayName, String
      const :description, String
      prop :message, T.nilable(String)
      const :result, MergeConditionResult
      const :conflicts, T.nilable(T::Array[String])
      const :isConflictResolvableInWeb, T.nilable(T::Boolean)
      const :webEditorConflictResolution, T.nilable(MergeConflictWebEditorResolution)
    end

    # Merge Conditions with visible failing sub conditions (provides visibility into underlying failures)
    class MergeConditionWithSubConditionsPayload < T::Struct
      const :type, MergeConditionType
      const :displayName, String
      const :description, String
      prop :message, T.nilable(String)
      const :result, MergeConditionResult
      const :failedSubConditions, T.nilable(T::Array[FailingSubConditionPayload])
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
      const :conditions, T::Array[T.any(GenericMergeConditionPayload, ConflictMergeConditionPayload, RepositoryRulesMergeConditionPayload, MergeConditionWithSubConditionsPayload)]
      const :defaultCommitAuthorEmail, T.nilable(String)
      const :commitMessageHeadline, T.nilable(String)
      const :commitMessageBody, T.nilable(String)
      const :possibleCommitAuthorEmails, T::Array[String]
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
      # turn URLs in messages into links
      merge_requirements_data.conditions.each do |condition|
        if condition.message
          condition.message = GitHub::Goomba::PullRequestMergeConditionMessagePipeline.to_html(condition.message)
        end
      end
      MergeRequirementsPayload.new(
        state: MergeRequirementsState.deserialize(merge_requirements_data.state.upcase.to_s),
        conditions: merge_requirements_data.conditions,
        defaultCommitAuthorEmail: merge_requirements_data.commit_author_email,
        commitMessageHeadline: merge_requirements_data.commit_message_headline,
        commitMessageBody: merge_requirements_data.commit_message_body,
        possibleCommitAuthorEmails: merge_requirements_data.possible_commit_author_emails
      )
    end
  end
end
