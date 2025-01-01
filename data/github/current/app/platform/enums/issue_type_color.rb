# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class IssueTypeColor < Platform::Enums::Base
      description "The possible color for an issue type"

      IssueType::COLORS.each do |key, _|
        value self.convert_string_to_enum_value(key.to_s), key.to_s, value: key.to_s
      end
    end
  end
end
