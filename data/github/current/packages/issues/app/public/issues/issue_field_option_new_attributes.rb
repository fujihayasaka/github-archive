# typed: strict
# frozen_string_literal: true

module Issues
  # Used to delete a specific issue field value by field_id
  class IssueFieldOptionNewAttributes < T::Struct
    prop :name, String
    prop :color, String
    prop :description, T.nilable(String)
    prop :priority, T.nilable(Integer)
  end
end
