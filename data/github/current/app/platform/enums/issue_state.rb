# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IssueState < Platform::Enums::Base
      description "The possible states of an issue."

      value "OPEN", "An issue that is still open", value: "open"
      value "CLOSED", "An issue that has been closed", value: "closed"
    end
  end
end
