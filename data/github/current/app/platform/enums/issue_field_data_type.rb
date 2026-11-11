# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class IssueFieldDataType < Platform::Enums::Base
      docs_category :issues
      description "The type of an issue field."

      IssueField::DATA_TYPES.each do |key, _|
        value self.convert_string_to_enum_value(key.to_s), key.to_s.titleize, value: key.to_sym
      end
    end
  end
end
