# typed: true
# frozen_string_literal: true

module PullRequests
  class AsyncMergeBoxPlaceholderComponent < ApplicationComponent
    attr_reader :pull_request, :gate_requests
    include MergeboxHelper

    def initialize(pull_request:, gate_requests:)
      @pull_request = pull_request
      @gate_requests = gate_requests
    end

    def pull_request_base_page_data_path
      pull_request_path(pull_request)
    end

    def default_merge_method(current_user:)
      default_merge_method_for_user(pull_request, current_user)
    end

    def alive_channels
      PullRequests::PageData::MergeBox::AliveChannelsPayload.build(
        pull_request:,
        base_repository: pull_request.base_repository,
        head_repository: pull_request.head_repository,
      )
    end
  end
end
