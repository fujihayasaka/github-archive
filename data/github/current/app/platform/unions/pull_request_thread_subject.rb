# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class PullRequestThreadSubject < Platform::Unions::Base
      docs_category :pulls
      description "The relation of a comment thread to a Pull Request."

      visibility :internal # TODO: internal for now

      possible_types Objects::PullRequestDiffThread
    end
  end
end
