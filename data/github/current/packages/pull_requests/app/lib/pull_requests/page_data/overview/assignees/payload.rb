# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview::Assignees
  class Payload
    class AssigneePayload < T::Struct
      const :id, Integer
      const :displayLogin, String
      const :avatarUrl, String
    end

    class AssigneesPayload < T::Struct
      const :assignees, T::Array[AssigneePayload]
    end

    sig do
      params(
        assignees_data: PullRequests::PageData::Overview::Assignees::Loader::AssigneesData,
      ).returns(AssigneesPayload)
    end
    def self.call(assignees_data)
      new(assignees_data:).call
    end

    sig do
      params(
        assignees_data: PullRequests::PageData::Overview::Assignees::Loader::AssigneesData,
      ).void
    end
    def initialize(assignees_data:)
      @assignees_data = assignees_data
    end

    sig { returns(AssigneesPayload) }
    def call
      AssigneesPayload.new(
        assignees: @assignees_data.assignees.map { |assignee| build_assignee(assignee) },
      )
    end

    private

    sig { params(assignee_data: Loader::AssigneeData).returns(AssigneePayload) }
    def build_assignee(assignee_data)
      AssigneePayload.new(
        id: assignee_data.id,
        displayLogin: assignee_data.display_login,
        avatarUrl: assignee_data.avatar_url,
      )
    end
  end
end
