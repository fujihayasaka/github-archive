# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class RenamedTitleSubject < Platform::Unions::Base
      description "An object which has a renamable title"

      possible_types(
        Objects::Issue,
        Objects::PullRequest,
      )
    end
  end
end
