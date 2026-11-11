# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CustomPropertyValueType < Platform::Enums::Base
      description "The allowed value types for a custom property definition."

      value "STRING", "A string value.", value: "string"
      value "MULTI_SELECT", "A multi-select value.", value: "multi_select"
      value "SINGLE_SELECT", "A single-select value.", value: "single_select"
      value "TRUE_FALSE", "A true/false value.", value: "true_false"
      value "URL", "A URL value.", value: "url"
    end
  end
end
