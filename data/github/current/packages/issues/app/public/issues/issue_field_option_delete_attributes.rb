# typed: strict
# frozen_string_literal: true

module Issues
  # Used to delete a specific issue field option
  class IssueFieldOptionDeleteAttributes < T::Struct
    prop :option_id, T.any(String, Integer)
    prop :field_id, T.any(String, Integer)
  end
end
