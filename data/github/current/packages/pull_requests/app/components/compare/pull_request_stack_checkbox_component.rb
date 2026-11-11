# typed: true
# frozen_string_literal: true

module Compare
  class PullRequestStackCheckboxComponent < ApplicationComponent
    include GitHub::Memoizer

    sig { params(current_repository: Repository, comparison: GitHub::Comparison).void }
    def initialize(current_repository:, comparison:)
      @current_repository = current_repository
      @comparison = comparison
    end

    sig { returns(Repository) }
    attr_reader :current_repository

    sig { returns(GitHub::Comparison) }
    attr_reader :comparison

    sig { returns(T::Boolean) }
    def render?
      return false if comparison.cross_repository?

      return false unless stacks_enabled?

      prev_pull = previous_pull_request
      !prev_pull.nil? && prev_pull.can_stack_on_top?
    end

    sig { returns(T.nilable(PullRequest)) }
    memoize def previous_pull_request
      PullRequest.find_by(
        repository: current_repository,
        head_ref: @comparison.base_ref
      )
    end

    def previous_pull_request_link
      if pull = previous_pull_request
        link_to(
          "##{pull.number}",
          pull_request_path(previous_pull_request),
          data: hovercard_data_attributes_for_issue_or_pr(pull.issue)
        )
      end
    end

    private

    def stacks_enabled?
      FeatureFlag.vexi.enabled?(
        :pull_request_stacks,
        [@current_repository, current_user].compact,
        default: false,
      )
    end
  end
end
