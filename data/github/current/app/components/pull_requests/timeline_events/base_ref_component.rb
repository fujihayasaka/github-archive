# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class BaseRefComponent < ApplicationComponent
    attr_reader :pull_request, :repository

    def initialize(pull_request:, repository:)
      @pull_request = pull_request
      @repository = repository
    end
  end
end
