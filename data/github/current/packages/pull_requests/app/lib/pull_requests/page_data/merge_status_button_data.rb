# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  class MergeStatusButtonData
    include GitHub::ResilienceMixin

    sig do
      params(pull_request: PullRequest, viewer: User).void
    end
    def initialize(pull_request:, viewer:)
      @pull_request = pull_request
      @viewer = viewer
    end

    sig { returns(PullRequests::PageData::MergeBox::AliveChannelsPayload::Data) }
    def channels
      @channels ||= T.let(PullRequests::PageData::MergeBox::AliveChannelsPayload.build(
        pull_request: @pull_request,
        base_repository: T.must(@pull_request.base_repository),
        head_repository: @pull_request.head_repository,
      ), T.nilable(PullRequests::PageData::MergeBox::AliveChannelsPayload::Data))
    end

    sig { returns(PullRequests::PageData::MergeBox::PullRequestPayload::MergeMethod) }
    def default_merge_method
      @default_merge_method ||= T.let(
        PullRequests::PageData::MergeBox::PullRequestPayload::MergeMethod.deserialize(
          with_async_database_error_fallback(
            PullRequest::MergeRequirements.new(@pull_request, nil, nil, nil, @viewer).merge_method,
            fallback: :MERGE
          ).sync.to_s.upcase
        ),
        T.nilable(PullRequests::PageData::MergeBox::PullRequestPayload::MergeMethod)
      )
    end

    sig { returns(String) }
    def head_sha
      @pull_request.head_sha
    end

    sig { returns(String) }
    def help_url
      GitHub.help_url
    end

    sig { returns(String) }
    def viewer_login
      @viewer.display_login
    end
  end
end
