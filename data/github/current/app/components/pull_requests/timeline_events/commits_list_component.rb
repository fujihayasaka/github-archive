# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class CommitsListComponent < ApplicationComponent
    attr_reader :pull_request, :commits

    def initialize(pull_request:, commits:)
      @pull_request = pull_request
      @commits = commits
    end

    def commit_count
      commits.count
    end

    def multiple_authors?
      commits.map(&:author_emails).flatten.uniq.size > 1
    end
  end
end
