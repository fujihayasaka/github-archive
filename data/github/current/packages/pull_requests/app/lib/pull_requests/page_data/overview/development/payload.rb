# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview::Development
  class Payload
    class RepositoryPayload < T::Struct
      const :owner, String
      const :name, String
    end

    class LinkedIssuePayload < T::Struct
      const :id, Integer
      const :number, Integer
      const :title, String
      const :url, String
      const :state, String
      const :stateReason, T.nilable(String)
      const :repository, RepositoryPayload
    end

    class DevelopmentPayload < T::Struct
      const :linkedIssues, T::Array[LinkedIssuePayload]
    end

    sig do
      params(
        development_data: PullRequests::PageData::Overview::Development::Loader::DevelopmentData,
      ).returns(DevelopmentPayload)
    end
    def self.call(development_data)
      new(development_data:).call
    end

    sig do
      params(
        development_data: PullRequests::PageData::Overview::Development::Loader::DevelopmentData,
      ).void
    end
    def initialize(development_data:)
      @development_data = development_data
    end

    sig { returns(DevelopmentPayload) }
    def call
      DevelopmentPayload.new(
        linkedIssues: @development_data.linked_issues.map { |issue| build_linked_issue(issue) },
      )
    end

    private

    sig { params(linked_issue: Loader::LinkedIssueData).returns(LinkedIssuePayload) }
    def build_linked_issue(linked_issue)
      LinkedIssuePayload.new(
        id: linked_issue.id,
        number: linked_issue.number,
        title: linked_issue.title,
        url: linked_issue.url,
        state: linked_issue.state.upcase,
        stateReason: linked_issue.state_reason&.upcase,
        repository: RepositoryPayload.new(
          owner: linked_issue.repository.owner,
          name: linked_issue.repository.name,
        ),
      )
    end
  end
end
