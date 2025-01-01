# typed: strict
# frozen_string_literal: true

module Issues
  class IssueFieldNumberValueAttributes < T::Struct
    prop :field_id, Integer
    prop :number_value, Numeric
  end
end
