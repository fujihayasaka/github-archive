# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class Closer < Platform::Unions::Base
      description "The object which triggered a `ClosedEvent`."

      possible_types(
        Objects::Commit,
        Objects::PullRequest,
        Objects::ProjectV2,
      )
    end
  end
end
