# typed: strict
# frozen_string_literal: true

module Issues
  class UpdateIssueAttributes < T::Struct
    prop :title, UpdateIssueAttribute[String], default: UpdateIssueAttribute::Keep[String].new
    prop :body, UpdateIssueAttribute[String], default: UpdateIssueAttribute::Keep[String].new
    prop :issue_fields, T::Array[T.any(IssueField::IssueFieldAttributesType, IssueFieldDeleteAttributes)], default: []
    prop :assignees, UpdateIssueAttribute[T::Array[Users::IUser]], default: UpdateIssueAttribute::Keep[T::Array[Users::IUser]].new
    prop :labels, UpdateIssueAttribute[T::Array[ILabel]], default: UpdateIssueAttribute::Keep[T::Array[ILabel]].new
    prop :milestone, UpdateIssueAttribute[IMilestone], default: UpdateIssueAttribute::Keep[IMilestone].new
    prop :issue_type, UpdateIssueAttribute[IIssueType], default: UpdateIssueAttribute::Keep[IIssueType].new
    prop :state, UpdateIssueAttribute[State], default: UpdateIssueAttribute::Keep[State].new
    prop :projects, UpdateIssueAttribute[T::Array[IProjectV2]], default: UpdateIssueAttribute::Keep[T::Array[IProjectV2]].new
  end
end
