# typed: strict
# frozen_string_literal: true

module Issues
  class UpdateIssueAttributes < T::Struct
    # The new title for the issue.
    prop :title, T.any(UpdateOptions::Keep, String), default: UpdateOptions::Keep

    # The new body for the issue.
    prop :body, T.any(UpdateOptions::Keep, UpdateOptions::Delete, String), default: UpdateOptions::Keep

    # The new value for an issue field on the issue, or a delete operation for a specific field.
    prop :issue_fields, T::Array[T.any(
      IssueField::IssueFieldAttributesType,
      IssueFieldDeleteAttributes,
    )], default: []

    # the new value for assignees
    prop :assignees, T.any(UpdateOptions::Keep, T::Array[Users::IUser]), default: UpdateOptions::Keep
  end
end
