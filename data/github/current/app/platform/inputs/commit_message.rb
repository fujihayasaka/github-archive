# typed: false
# frozen_string_literal: true

module Platform
  module Inputs
    class CommitMessage < Platform::Inputs::Base
      graphql_name "CommitMessage"
      description "A message to include with a new commit"

      argument :headline, String, "The headline of the message.", required: true
      argument :body, String, "The body of the message.", required: false

      # Coerce to a string in the format required by git.
      def prepare
        [headline, body].compact.join("\n\n")
      end
    end
  end
end
