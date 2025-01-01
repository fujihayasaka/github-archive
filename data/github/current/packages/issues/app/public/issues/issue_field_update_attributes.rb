# typed: strict
# frozen_string_literal: true

module Issues
  # Used to update an existing issue field
  class IssueFieldUpdateAttributes < T::Struct
    prop :name, T.nilable(String)
    prop :description, T.nilable(String)
    prop :priority, T.nilable(Integer)
  end
end
