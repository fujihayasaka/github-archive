# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class IssueFieldVisibility < Platform::Enums::Base
      docs_category :issues
      description "The visibility of an issue field."

      IssueField::VISIBILITIES.each do |key, _|
        value self.convert_string_to_enum_value(key.to_s), key.to_s.titleize, value: key.to_sym
      end
    end
  end
end
