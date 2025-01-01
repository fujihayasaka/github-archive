# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectState < Platform::Enums::Base
      description "State of the project; either 'open' or 'closed'"

      value "OPEN", "The project is open.", value: "open"
      value "CLOSED", "The project is closed.", value: "closed"
    end
  end
end
