# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  module BannersLoaders
    class HiddenCharactersLoader
      sig { params(pull_request: PullRequest).returns(T::Hash[Symbol, T::Boolean]) }
      def self.build(pull_request:)
        contains_hidden_characters?(pull_request:) ? { render: true } : { render: false }
      end

      sig { params(pull_request: PullRequest).returns(T::Boolean) }
      def self.contains_hidden_characters?(pull_request:)
        pull_request.head_ref_contains_non_printing_chars?
      end
    end
  end
end
