# typed: strict
# frozen_string_literal: true

require "pull_requests/v1/development_pb"

module PullRequests::PageData::Overview::Development
  # Builds the protobuf DevelopmentResponse from the same Loader::DevelopmentData
  # that Payload consumes, mirroring Payload's per-field transforms. This keeps
  # the proto branch a pure re-encoding of the exact same data the legacy JSON
  # renders.
  #
  # The legacy Payload upper-cases `state`/`state_reason` strings; here those
  # map onto the IssueState/IssueStateReason enums instead. A nil state_reason
  # becomes the UNSPECIFIED zero value (omitted from JSON), matching the legacy
  # null.
  class ProtoPayload
    STATE = T.let({
      "open" => :ISSUE_STATE_OPEN,
      "closed" => :ISSUE_STATE_CLOSED,
    }.freeze, T::Hash[String, Symbol])

    STATE_REASON = T.let({
      "completed" => :ISSUE_STATE_REASON_COMPLETED,
      "duplicate" => :ISSUE_STATE_REASON_DUPLICATE,
      "not_planned" => :ISSUE_STATE_REASON_NOT_PLANNED,
      "reopened" => :ISSUE_STATE_REASON_REOPENED,
    }.freeze, T::Hash[String, Symbol])

    sig do
      params(
        development_data: Loader::DevelopmentData,
      ).returns(Github::PullRequests::V1::DevelopmentResponse)
    end
    def self.call(development_data)
      new(development_data:).call
    end

    sig { params(development_data: Loader::DevelopmentData).void }
    def initialize(development_data:)
      @development_data = T.let(development_data, Loader::DevelopmentData)
    end

    sig { returns(Github::PullRequests::V1::DevelopmentResponse) }
    def call
      Github::PullRequests::V1::DevelopmentResponse.new(
        linked_issues: @development_data.linked_issues.map { |issue| build_linked_issue(issue) },
      )
    end

    private

    sig { params(data: Loader::LinkedIssueData).returns(Github::PullRequests::V1::LinkedIssue) }
    def build_linked_issue(data)
      state_reason = data.state_reason

      Github::PullRequests::V1::LinkedIssue.new(
        id: data.id,
        number: data.number,
        title: data.title,
        url: data.url,
        state: STATE.fetch(data.state.downcase, :ISSUE_STATE_UNSPECIFIED),
        state_reason: state_reason ? STATE_REASON.fetch(state_reason.downcase, :ISSUE_STATE_REASON_UNSPECIFIED) : :ISSUE_STATE_REASON_UNSPECIFIED,
        repository: Github::PullRequests::V1::Repository.new(
          owner: data.repository.owner,
          name: data.repository.name,
        ),
      )
    end
  end
end
