# typed: true
# frozen_string_literal: true

module PullRequests
  class RevisionMarkerComponent < ApplicationComponent
    def initialize(pull_request:, last_seen_commit_oid:)
      @pull_request = pull_request
      @last_seen_commit_oid = last_seen_commit_oid
    end

    def compare_path
      "#{@pull_request.async_path_uri.sync}/files/#{@last_seen_commit_oid}..HEAD" # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end
end
