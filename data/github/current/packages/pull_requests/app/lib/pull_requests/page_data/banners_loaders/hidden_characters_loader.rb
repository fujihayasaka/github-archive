# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  module BannersLoaders
    class HiddenCharactersLoader
      extend T::Sig

      sig { params(pull_request: PullRequest, repository: Repository).returns(T::Hash[Symbol, T::Boolean]) }
      def self.build(pull_request:, repository:)
        contains_hidden_characters?(pull_request:, repository:) ? { render: true } : { render: false }
      end

      sig { params(pull_request: PullRequest, repository: Repository).returns(T::Boolean) }
      def self.contains_hidden_characters?(pull_request:, repository:)
        GitHub.flipper[:collect_non_printing_chars_metrics].enabled?(repository) &&
        pull_request.head_ref_contains_non_printing_chars? &&
        GitHub.flipper[:display_non_printing_chars_warning].enabled?(repository)
      end
    end
  end
end
