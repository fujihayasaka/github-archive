# typed: strict
# frozen_string_literal: true

module Issues
  class CreateIssueFieldValueAttributes < T::Struct
    prop :field_id, Integer
    prop :text_value, T.nilable(String)
    prop :single_select_option_id, T.nilable(Integer)
  end
end
