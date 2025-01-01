# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  module BannersLoaders
    class HiddenCharactersLoader
      sig { params(pull_request: PullRequest, repository: Repository).returns(T::Hash[Symbol, T::Boolean]) }
      def self.build(pull_request:, repository:)
        contains_hidden_characters?(pull_request:, repository:) ? { render: true } : { render: false }
      end

      sig { params(pull_request: PullRequest, repository: Repository).returns(T::Boolean) }
      def self.contains_hidden_characters?(pull_request:, repository:)
        FeatureFlag.vexi.enabled_or_raise?(:collect_non_printing_chars_metrics, repository) && # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        pull_request.head_ref_contains_non_printing_chars? &&
        FeatureFlag.vexi.enabled_or_raise?(:display_non_printing_chars_warning, repository) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      end
    end
  end
end
