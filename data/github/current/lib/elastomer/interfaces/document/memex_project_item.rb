# typed: strict
# frozen_string_literal: true

require_relative "memex_project_column"

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        autoload :DraftIssueState, "elastomer/interfaces/document/memex_project_item/draft_issue_state"
        autoload :DependencyIssue, "elastomer/interfaces/document/memex_project_item/dependency_issue"
        autoload :IssueState, "elastomer/interfaces/document/memex_project_item/issue_state"
        autoload :PullRequestState, "elastomer/interfaces/document/memex_project_item/pull_request_state"
        autoload :IssueStateReason, "elastomer/interfaces/document/memex_project_item/issue_state_reason"
        autoload :ContentType, "elastomer/interfaces/document/memex_project_item/content_type"
        autoload :Content, "elastomer/interfaces/document/memex_project_item/content"
        autoload :FieldValues, "elastomer/interfaces/document/memex_project_item/field_values"
        autoload :FieldValue, "elastomer/interfaces/document/memex_project_item/field_value"
        autoload :Root, "elastomer/interfaces/document/memex_project_item/root"
        autoload :Metadata, "elastomer/interfaces/document/memex_project_item/metadata"

        AssigneesValue = T.type_alias { T.nilable(T::Array[Elastomer::Interfaces::Document::Assignee]) }
        DateValue = T.type_alias { T.nilable(String) }
        IssueFieldSingleSelectValue = T.type_alias { T.nilable(Elastomer::Interfaces::Document::IssueFieldSingleSelect) }
        IssueTypeValue = T.type_alias { T.nilable(Elastomer::Interfaces::Document::IssueType) }
        IterationValue = T.type_alias { T.nilable(Elastomer::Interfaces::Document::Iteration) }
        LabelsValue = T.type_alias { T.nilable(T::Array[Elastomer::Interfaces::Document::Label]) }
        LinkedPullRequestsValue = T.type_alias { T.nilable(T::Array[Elastomer::Interfaces::Document::LinkedPullRequests]) }
        MilestoneValue = T.type_alias { T.nilable(Elastomer::Interfaces::Document::Milestone) }
        NumberValue = T.type_alias { T.nilable(Numeric) }
        ParentIssueValue = T.type_alias { T.nilable(Elastomer::Interfaces::Document::ParentIssue) }
        RepositoryValue = T.type_alias { T.nilable(Elastomer::Interfaces::Document::Repository) }
        ReviewersValue = T.type_alias { T.nilable(T::Array[Elastomer::Interfaces::Document::Reviewers]) }
        SingleSelectValue = T.type_alias { T.nilable(Elastomer::Interfaces::Document::SingleSelect) }
        SubIssuesProgressValue = T.type_alias { T.nilable(Elastomer::Interfaces::Document::SubIssuesProgress) }
        TextValue = T.type_alias { T.nilable(String) }
        TitleValue = T.type_alias { String }
        TrackedByValue = T.type_alias { T.nilable(T::Array[String]) }
        TracksValue = T.type_alias { T.nilable(Elastomer::Interfaces::Document::Tracks) }

        Value = T.type_alias do
          T.any(
            AssigneesValue,
            DateValue,
            IssueFieldSingleSelectValue,
            IssueTypeValue,
            IterationValue,
            LabelsValue,
            LinkedPullRequestsValue,
            MilestoneValue,
            NumberValue,
            ParentIssueValue,
            RepositoryValue,
            ReviewersValue,
            SingleSelectValue,
            SubIssuesProgressValue,
            TextValue,
            TitleValue,
            TrackedByValue,
            TracksValue,
          )
        end

        ContentModel = T.type_alias do
          T.any(
            ::DraftIssue,
            ::Issue,
            ::PullRequest,
          )
        end

        ContentState = T.type_alias do
          T.any(
            DraftIssueState,
            IssueState,
            PullRequestState,
          )
        end
      end
    end
  end
end
