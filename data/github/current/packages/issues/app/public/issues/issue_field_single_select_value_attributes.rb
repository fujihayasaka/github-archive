# typed: strict
# frozen_string_literal: true

module Issues
  # Represents attributes for creating a single select field value
  class IssueFieldSingleSelectValueAttributes < T::Struct
    prop :field_id, Integer
    prop :option_id, Integer
  end
end
