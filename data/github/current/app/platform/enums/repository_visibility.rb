# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryVisibility < Platform::Enums::Base
      description "The repository's visibility level."

      value "PRIVATE", "The repository is visible only to those with explicit access.", value: "private"
      value "PUBLIC", "The repository is visible to everyone.", value: "public"
      value "INTERNAL", "The repository is visible only to users in the same enterprise.", value: "internal"
    end
  end
end
