# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CheckSuiteVisibility < Platform::Enums::Base
      description "Indicates whether the check suite should be hidden outside of the Actions tab."

      visibility :internal

      value "DEFAULT", "Logic in the monolith determines visibility.", value: 0
      value "VISIBLE", "Overrides the default and will ensure the CheckSuite is marked visible in the monolith.", value: 1
      value "HIDDEN", "Overrides the default and will ensure the CheckSuite is marked as hidden in the monolith.", value: 2
    end
  end
end
