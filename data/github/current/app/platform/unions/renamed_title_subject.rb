# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class RenamedTitleSubject < Platform::Unions::Base
      docs_category :issues
      description "An object which has a renamable title"

      possible_types(
        Objects::Issue,
        Objects::PullRequest,
      )
    end
  end
end
