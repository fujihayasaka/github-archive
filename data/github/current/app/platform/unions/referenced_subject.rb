# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class ReferencedSubject < Platform::Unions::Base
      description "Any referencable object"

      possible_types(
        Objects::Issue,
        Objects::PullRequest,
      )
    end
  end
end
