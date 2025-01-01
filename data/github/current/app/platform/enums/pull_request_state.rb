# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestState < Platform::Enums::Base
      description "The possible states of a pull request."

      value "OPEN", "A pull request that is still open.", value: "open"
      value "CLOSED", "A pull request that has been closed without being merged.", value: "closed"
      value "MERGED", "A pull request that has been closed by being merged.", value: "merged"
    end
  end
end
