# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Description
  class Loader
    sig { returns(PullRequest) }
    attr_reader :pull_request

    class DescriptionData < T::Struct
      const :body, T.nilable(String)
      const :body_html, T.nilable(String)
      const :body_version, T.nilable(String)
    end

    sig { params(pull_request: PullRequest, current_user: T.nilable(::User), cap_filter: T.nilable(ConditionalAccess::Web::Filter)).returns(DescriptionData) }
    def self.load(pull_request:, current_user: nil, cap_filter: nil)
      new(pull_request:, current_user:, cap_filter:).load
    end

    sig { params(pull_request: PullRequest, current_user: T.nilable(::User), cap_filter: T.nilable(ConditionalAccess::Web::Filter)).void }
    def initialize(pull_request:, current_user: nil, cap_filter: nil)
      @pull_request = pull_request
      @current_user = current_user
      @cap_filter = cap_filter
    end

    sig { returns(DescriptionData) }
    def load
      DescriptionData.new(
        body: @pull_request.body,
        body_html: @pull_request.body_html(context: @pull_request.body_html_context(viewer: @current_user, cap_filter: @cap_filter)) || GitHub::HTMLSafeString::EMPTY,
        body_version: @pull_request.issue&.body_version,
      )
    end
  end
end
