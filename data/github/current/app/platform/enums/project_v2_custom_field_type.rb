# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2CustomFieldType < Platform::Enums::Base
      description "The type of a project field."

      value "TEXT", "Text", value: "text"
      value "SINGLE_SELECT", "Single Select", value: "single_select"
      value "NUMBER", "Number", value: "number"
      value "DATE", "Date", value: "date"
    end
  end
end
