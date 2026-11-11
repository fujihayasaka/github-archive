# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class BaseRefComponent < ApplicationComponent
    attr_reader :pull_request, :repository, :use_stack_base

    def initialize(pull_request:, repository:, use_stack_base: false)
      @pull_request = pull_request
      @repository = repository
      @use_stack_base = use_stack_base
    end

    def display_ref_name
      if use_stack_base
        pull_request.display_stack_or_pull_base_ref_name
      else
        pull_request.display_base_ref_name
      end
    end
  end
end
