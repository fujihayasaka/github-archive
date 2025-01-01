# typed: strict
# frozen_string_literal: true

module Issues
  # Represents attributes for creating a text field value
  class IssueFieldTextValueAttributes < T::Struct
    prop :field_id, Integer
    prop :text_value, String
  end
end
