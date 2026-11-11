# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class TeamDiscussion
      DeprecationNotice = {
        start_date: Date.new(2024, 2, 27),
        reason: "The Team Discussions feature is deprecated in favor of Organization Discussions.",
        superseded_by: "Follow the guide at https://github.blog/changelog/2023-02-08-sunset-notice-team-discussions/ to find a suitable replacement.",
        owner: "deborah-digges",
      }
      def self.raise_missing_mutation_argument(argument, mutation_class)
        raise Errors::ArgumentError.new "Argument '#{argument}' on InputObject '#{mutation_class.name.demodulize}' " \
          "is required. Expected type String"
      end
    end
  end
end
