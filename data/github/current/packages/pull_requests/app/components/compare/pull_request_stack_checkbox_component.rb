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

    sig { returns(T::Boolean) }
    def stacked_by_default?
      params[:stack].present?
    end

    sig { returns(T.nilable(PullRequest)) }
    memoize def previous_pull_request
      PullRequest.open_pulls.find_by(
        repository: current_repository,
        head_ref: @comparison.base_ref
      )
    end

    sig { returns(String) }
    def checkbox_label
      pull = T.must(previous_pull_request)

      if pull.stacked?
        "Add this pull request to an existing stack"
      else
        "Start a pull request stack"
      end
    end

    sig { returns(ActiveSupport::SafeBuffer) }
    def checkbox_caption
      pull = T.must(previous_pull_request)
      pull_link = link_to(
        "##{pull.number}",
        pull_request_path(pull),
        data: hovercard_data_attributes_for_issue_or_pr(pull.issue),
      )

      return safe_join(["This pull request will be stacked with ", pull_link]) unless pull.stacked?

      stack = T.must(pull.stack)
      safe_join(["This pull request will be stacked with ", pull_link, " and ", pluralize(stack.entry_count - 1, "other pull request")])
    end

    private

    def stacks_enabled?
      PullRequests::Stacks.enabled?(@current_repository)
    end
  end
end
