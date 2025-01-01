# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestUpdateState < Platform::Enums::Base
      description "The possible target states when updating a pull request."

      value "OPEN", "A pull request that is still open.", value: "open"
      value "CLOSED", "A pull request that has been closed without being merged.", value: "closed"
    end
  end
end
