# typed: strict
# frozen_string_literal: true

module Issues
  # Represents attributes for creating a multi-select field value
  class IssueFieldMultiSelectValueAttributes < T::Struct
    prop :field_id, Integer
    prop :option_ids, T::Array[Integer]
  end
end
