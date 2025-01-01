# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryAdvisoryState < Platform::Enums::Base
      description "The possible states of a maintainer advisory."

      visibility :internal


      value "OPEN", "A maintainer advisory that is still open.", value: "open"
      value "CLOSED", "A maintainer advisory that has been closed.", value: "closed"
      value "PUBLISHED", "A maintainer advisory that has been published.", value: "published"
    end
  end
end
