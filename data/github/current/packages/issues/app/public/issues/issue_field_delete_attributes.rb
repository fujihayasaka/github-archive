# typed: strict
# frozen_string_literal: true

module Issues
  # Used to delete a specific issue field value by field_id
  class IssueFieldDeleteAttributes < T::Struct
    # The ID of the field to delete
    prop :field_id, Integer
  end
end
