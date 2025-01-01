# typed: strict
# frozen_string_literal: true

module Issues
  class IssueFieldDateValueAttributes < T::Struct
    prop :field_id, Integer
    prop :date_value, String # ISO 8601 date string
  end
end
