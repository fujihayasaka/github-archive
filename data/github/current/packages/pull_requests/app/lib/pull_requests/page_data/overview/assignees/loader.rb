# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview::Assignees
  class Loader
    include GitHub::ResilienceMixin

    sig { returns(PullRequest) }
    attr_reader :pull_request

    class AssigneeData < T::Struct
      const :id, Integer
      const :display_login, String
      const :avatar_url, String
    end

    class AssigneesData < T::Struct
      const :assignees, T::Array[AssigneeData]
    end

    sig { params(pull_request: PullRequest).returns(AssigneesData) }
    def self.load(pull_request:)
      new(pull_request:).load
    end

    sig { params(pull_request: PullRequest).void }
    def initialize(pull_request:)
      @pull_request = pull_request
    end

    sig { returns(AssigneesData) }
    def load
      issue = @pull_request.issue
      raise ArgumentError, "Pull request issue is missing" if issue.nil?

      repository = @pull_request.repository
      raise ArgumentError, "Pull request repository is missing" if repository.nil?

      assignees = issue.assignees.to_a
      prefill_associations(assignees)

      AssigneesData.new(
        assignees: assignees.map { |assignee| build_assignee(assignee) },
      )
    end

    private

    sig { params(users: T::Array[User]).void }
    def prefill_associations(users)
      return if users.empty?

      GitHub::PrefillAssociations.prefill_associations(users, [{ user_status: :organization }])
    end

    sig { params(assignee: User).returns(AssigneeData) }
    def build_assignee(assignee)
      AssigneeData.new(
        id: assignee.id,
        display_login: assignee.display_login_legacy,
        avatar_url: assignee.primary_avatar_url(60),
      )
    end
  end
end
