# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class RuleSource < Platform::Unions::Base
      description "Types which can have `RepositoryRule` objects."

      possible_types(
        Objects::Repository,
        Objects::Organization,
        Objects::Enterprise,
      )
    end
  end
end
