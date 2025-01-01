# typed: true
# frozen_string_literal: true

module Issues
  class IssueTransferPossibleReposComponent < ApplicationComponent
    include ::TextHelper

    attr_reader :issue

    def initialize(issue:, viewer: nil, filter: nil)
      @issue = issue
      @filter = filter
      @viewer = viewer
    end

    private

    def is_empty?
      @repos.empty
    end

    memoize def repos
      possible_transfer_repositories_for_viewer(filter: @filter)
    end

    def possible_transfer_repositories_for_viewer(filter: nil)
      repos = @issue.async_possible_transfer_repositories(viewer: @viewer, query: filter).sync
      repos
    end
  end
end
