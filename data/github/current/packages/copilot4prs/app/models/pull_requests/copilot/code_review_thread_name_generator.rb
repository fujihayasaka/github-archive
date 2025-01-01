# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    # Public: Generate a name for a Copilot conversation that provides code review. The name will uniquely identify
    # which code range is being reviewed.
    class CodeReviewThreadNameGenerator
      include GitHub::Memoizer

      DEFAULT_NAME = "Code review"

      sig do
        params(
          pull_request: T.nilable(PullRequest),
          comparison: T.nilable(T.any(GitHub::Comparison, PullRequest::Comparison))
        ).returns(String)
      end
      def self.call(pull_request: nil, comparison: nil)
        new(pull_request: pull_request, comparison: comparison).call
      end

      sig do
        params(
          pull_request: T.nilable(PullRequest),
          comparison: T.nilable(T.any(GitHub::Comparison, PullRequest::Comparison))
        ).void
      end
      def initialize(pull_request: nil, comparison: nil)
        @pull_request = pull_request
        @comparison = comparison
      end

      sig { returns String }
      def call
        return DEFAULT_NAME if @pull_request.nil? && @comparison.nil?
        return DEFAULT_NAME if @comparison.is_a?(PullRequest::Comparison) && @comparison.pull.nil?

        base_repository = self.base_repository
        return DEFAULT_NAME unless base_repository

        "#{base_repository.name_with_display_owner} #{head_branch_name} review #{commit_range}"
      end

      private

      sig { returns String }
      def head_branch_name
        if @comparison.is_a?(GitHub::Comparison)
          @comparison.display_head_ref
        else
          pull_request = T.must_because(self.pull_request) do
            "#call returns early when neither comparison nor PR given"
          end
          pull_request.head_ref_name
        end
      end

      sig { returns String }
      def commit_range
        head_repo_prefix = if cross_repository?
          head_repository = self.head_repository
          if head_repository
            "#{head_repository.owner_display_login}:#{head_repository.name}:"
          end
        end

        "(#{abbreviated_base_sha}..#{head_repo_prefix}#{abbreviated_head_sha})"
      end

      sig { returns T::Boolean }
      def cross_repository?
        if @comparison.is_a?(GitHub::Comparison)
          @comparison.cross_repository?
        else
          pull_request = T.must_because(self.pull_request) do
            "#call returns early when neither comparison nor PR given"
          end
          pull_request.cross_repo?
        end
      end

      sig { returns T.nilable(Repository) }
      def base_repository
        if @comparison.is_a?(GitHub::Comparison)
          @comparison.base_repo
        else
          pull_request = T.must_because(self.pull_request) do
            "#call returns early when neither comparison nor PR given"
          end
          pull_request.base_repository
        end
      end

      sig { returns T.nilable(Repository) }
      def head_repository
        if @comparison.is_a?(GitHub::Comparison)
          @comparison.head_repo
        else
          pull_request = T.must_because(self.pull_request) do
            "#call returns early when neither comparison nor PR given"
          end
          pull_request.head_repository
        end
      end

      sig { returns String }
      def abbreviated_base_sha
        base_sha = if @comparison.is_a?(GitHub::Comparison)
          @comparison.base_sha
        else
          pull_request = T.must_because(self.pull_request) do
            "#call returns early when neither comparison nor PR given"
          end
          pull_request.base_sha
        end
        base_sha.first(Commit::ABBREVIATED_OID_LENGTH)
      end

      sig { returns String }
      def abbreviated_head_sha
        head_sha = if @comparison.is_a?(GitHub::Comparison)
          @comparison.head_sha
        else
          pull_request = T.must_because(self.pull_request) do
            "#call returns early when neither comparison nor PR given"
          end
          pull_request.head_sha
        end
        head_sha.first(Commit::ABBREVIATED_OID_LENGTH)
      end

      sig { returns T.nilable(PullRequest) }
      memoize def pull_request
        return @pull_request if @pull_request
        @comparison.pull if @comparison.is_a?(PullRequest::Comparison)
      end
    end
  end
end
