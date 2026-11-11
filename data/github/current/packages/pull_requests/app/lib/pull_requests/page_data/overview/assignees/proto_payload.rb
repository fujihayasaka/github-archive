# typed: strict
# frozen_string_literal: true

require "pull_requests/v1/assignees_pb"

module PullRequests::PageData::Overview::Assignees
  # Builds the protobuf AssigneesResponse from the same Loader::AssigneesData
  # that Payload consumes, mirroring Payload's per-field transforms. This keeps
  # the proto branch a pure re-encoding of the exact same data the legacy JSON
  # renders.
  class ProtoPayload
    sig do
      params(
        assignees_data: Loader::AssigneesData,
      ).returns(Github::PullRequests::V1::AssigneesResponse)
    end
    def self.call(assignees_data)
      new(assignees_data:).call
    end

    sig { params(assignees_data: Loader::AssigneesData).void }
    def initialize(assignees_data:)
      @assignees_data = T.let(assignees_data, Loader::AssigneesData)
    end

    sig { returns(Github::PullRequests::V1::AssigneesResponse) }
    def call
      Github::PullRequests::V1::AssigneesResponse.new(
        assignees: @assignees_data.assignees.map { |assignee| build_assignee(assignee) },
      )
    end

    private

    sig { params(data: Loader::AssigneeData).returns(Github::PullRequests::V1::Assignee) }
    def build_assignee(data)
      Github::PullRequests::V1::Assignee.new(
        id: data.id,
        display_login: data.display_login,
        avatar_url: data.avatar_url,
      )
    end
  end
end
