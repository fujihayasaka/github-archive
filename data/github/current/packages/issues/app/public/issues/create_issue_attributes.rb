# typed: strict
# frozen_string_literal: true

module Issues
  class CreateIssueAttributes < T::Struct
    prop :title, String
    prop :body, T.nilable(String)
    prop :repository, Repositories::IRepository
    prop :issue_type, T.nilable(IIssueType)
    prop :labels, T::Array[ILabel], default: []
    prop :milestone, T.nilable(IMilestone)
    prop :assignees, T::Array[Users::IUser], default: []
  end
end
