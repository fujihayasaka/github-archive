# typed: true
# frozen_string_literal: true

module PullRequests
  class ParentPrComponent < ApplicationComponent
    include OcticonsHelper
    include GitHub::Memoizer

    def initialize(pull_request:)
      @pull_request = pull_request
    end

    private

    def render?
      parent_pull_request.present?
    end

    memoize def parent_pull_request
      return if @pull_request.cross_repo?
      return unless @pull_request.base_ref_name != @pull_request.repository.default_branch

      @pull_request.repository.pull_requests.for_branch(@pull_request.base_ref_name).last
    end

    def octicon_name
      case parent_pull_request.state
      when :merged
        "git-merge"
      when :open
        return "git-pull-request-draft" if parent_pull_request&.draft?
        return "git-merge-queue" if parent_pull_request&.in_merge_queue?

        "git-pull-request"
      when :closed
        "git-pull-request-closed"
      end
    end
  end
end
