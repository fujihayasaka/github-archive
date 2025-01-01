# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectV2State < Platform::Enums::Base
      description "The possible states of a project v2."

      value "OPEN", "A project v2 that is still open",
        value: "open"
      value "CLOSED", "A project v2 that has been closed",
        value: "closed"
    end
  end
end
