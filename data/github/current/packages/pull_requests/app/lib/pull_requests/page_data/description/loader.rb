# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Description
  class Loader

    sig { returns(PullRequest) }
    attr_reader :pull_request

    class DescriptionData < T::Struct
      const :body_html, T.nilable(String)
    end

    sig { params(pull_request: PullRequest).returns(DescriptionData) }
    def self.load(pull_request:)
      description = new(pull_request:)
      description.load
    end

    sig { params(pull_request: PullRequest).void }
    def initialize(pull_request:)
      @pull_request = pull_request
    end

    sig { returns(DescriptionData) }
    def load
      DescriptionData.new(
        body_html: @pull_request.body_html,
      )
    end
  end
end
