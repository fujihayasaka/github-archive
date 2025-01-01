# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class IssueFieldSingleSelectOptionColor < Platform::Enums::Base
      description "The display color of a single-select field option."
      visibility :under_development

      IssueFieldOption::COLORS.each do |key, _|
        value self.convert_string_to_enum_value(key.to_s), key.to_s, value: key.to_s
      end
    end
  end
end
