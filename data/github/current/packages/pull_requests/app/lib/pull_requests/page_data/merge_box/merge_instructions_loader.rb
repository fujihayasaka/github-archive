# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::MergeBox
  class MergeInstructionsLoader
    class MergeInstructionsData < T::Struct
      const :pull_request, PullRequest
      const :comparison, GitHub::Comparison
      const :viewer, User
      const :push_protocols, T::Array[PullRequests::PageData::MergeBox::ProtocolSelector::Protocol]
    end

    sig do
      params(
        viewer: User,
        pull_request: PullRequest,
      ).returns(MergeInstructionsData)
    end
    def self.load(viewer:, pull_request:)
      new(viewer:, pull_request:).load
    end

    sig do params(
      viewer: User,
      pull_request: PullRequest
    ).void
    end
    def initialize(viewer:, pull_request:)
      @viewer = viewer
      @pull_request = pull_request
    end

    sig { returns(User) }
    attr_reader :viewer

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(MergeInstructionsData) }
    def load
      preload_data
      MergeInstructionsData.new(
        pull_request: pull_request,
        comparison: pull_request.comparison,
        viewer: viewer,
        push_protocols: PullRequests::PageData::MergeBox::ProtocolSelector.new(repository: T.must(pull_request.repository),
        user: viewer).protocols
      )
    end

    sig { void }
    def preload_data
      pull_request.issue
      pull_request.base_repository
      pull_request.repository&.ssh_url
    end
  end
end
