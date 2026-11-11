# typed: strict
# frozen_string_literal: true

module Issues
  # Used to create a new issue field
  class IssueFieldNewAttributes < T::Struct
    prop :name, String
    prop :data_type, String
    prop :description, T.nilable(String)
    prop :priority, T.nilable(Integer)
  end
end
