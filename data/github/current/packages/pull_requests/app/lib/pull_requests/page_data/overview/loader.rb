# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview
  class Loader
    include PullRequests::PageData::Telemetry

    sig { returns(PullRequest) }
    attr_reader :pull_request

    class OverviewData < T::Struct
      const :description, T.nilable(String)
    end

    sig { params(pull_request: PullRequest, current_user: T.nilable(::User)).returns(OverviewData) }
    def self.load(pull_request:, current_user: nil)
      new(pull_request:, current_user:).load
    end

    sig { params(pull_request: PullRequest, current_user: T.nilable(::User)).void }
    def initialize(pull_request:, current_user: nil)
      @pull_request = pull_request
      @current_user = current_user
    end

    sig { returns(OverviewData) }
    def load
      OverviewData.new(
        description: @pull_request.body_html,
      )
    end
  end
end
