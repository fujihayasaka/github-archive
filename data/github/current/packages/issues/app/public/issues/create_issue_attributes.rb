# typed: strict
# frozen_string_literal: true

module Issues
  class CreateIssueAttributes < T::Struct
    prop :title, String
    prop :body, T.nilable(String)
    prop :repository, Repositories::IRepository
    prop :issue_type, T.nilable(IIssueType)
    prop :issue_fields, T.nilable(T::Array[IssueField::IssueFieldAttributesType])
    prop :labels, T.nilable(T::Array[ILabel])
    prop :milestone, T.nilable(IMilestone)
    prop :assignee, T.nilable(Users::IUser)
    prop :assignees, T.nilable(T::Array[Users::IUser])
    prop :parent_issue, T.nilable(IIssue)
    prop :is_duplicated, T::Boolean, default: false
    prop :body_template_name, T.nilable(String)
    prop :template_name, T.nilable(String)
    prop :created_at, T.nilable(T.any(String, ActiveSupport::TimeWithZone, Time))
  end
end
