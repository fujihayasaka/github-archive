# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class IssueFieldDataType < Platform::Enums::Base
      description "The type of an issue field."
      visibility :under_development

      IssueField::DATA_TYPES.each do |key, _|
        value self.convert_string_to_enum_value(key.to_s), key.to_s.titleize, value: key.to_sym
      end
    end
  end
end
