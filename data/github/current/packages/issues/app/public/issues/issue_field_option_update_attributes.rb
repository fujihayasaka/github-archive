# typed: strict
# frozen_string_literal: true

module Issues
  # Used to update a specific issue field option
  class IssueFieldOptionUpdateAttributes < T::Struct
    prop :name, String
    prop :color, String
    prop :priority, T.nilable(Integer)
    prop :description, T.nilable(String)
    prop :option_id, Integer
  end
end
