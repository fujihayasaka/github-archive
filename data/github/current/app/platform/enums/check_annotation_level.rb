# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CheckAnnotationLevel < Platform::Enums::Base
      description "Represents an annotation's information level."

      value "FAILURE", "An annotation indicating an inescapable error.", value: "failure"
      value "NOTICE", "An annotation indicating some information.", value: "notice"
      value "WARNING", "An annotation indicating an ignorable error.", value: "warning"
    end
  end
end
