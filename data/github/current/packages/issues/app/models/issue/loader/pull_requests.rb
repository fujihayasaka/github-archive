# typed: true
# frozen_string_literal: true

class Issue::Loader::PullRequests < Issue::Loader::Base
  def initialize(context, pull_request_ids: [])
    @context = context
    @pull_request_ids = pull_request_ids
  end

  def self.load_for(context, pull_request_ids: [])
    super new(context, pull_request_ids: pull_request_ids)
  end

  def load
    PullRequest.strict_loading.
      where(id: @pull_request_ids).
      index_by(&:id).tap do |pull_requests_by_id|
        @context.preload_attr(:pull_requests_by_id, pull_requests_by_id)
      end
  end
end
