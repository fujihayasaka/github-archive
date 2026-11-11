# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview::Development
  class Loader
    include GitHub::ResilienceMixin

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(T.nilable(::User)) }
    attr_reader :viewer

    sig { returns(T.nilable(ConditionalAccess::Web::Filter)) }
    attr_reader :cap_filter

    class RepositoryData < T::Struct
      const :owner, String
      const :name, String
    end

    class LinkedIssueData < T::Struct
      const :id, Integer
      const :number, Integer
      const :title, String
      const :url, String
      const :state, String
      const :state_reason, T.nilable(String)
      const :repository, RepositoryData
    end

    class DevelopmentData < T::Struct
      const :linked_issues, T::Array[LinkedIssueData]
    end

    sig do
      params(
        pull_request: PullRequest,
        viewer: T.nilable(::User),
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
      ).returns(DevelopmentData)
    end
    def self.load(pull_request:, viewer:, cap_filter:)
      new(pull_request:, viewer:, cap_filter:).load
    end

    sig do
      params(
        pull_request: PullRequest,
        viewer: T.nilable(::User),
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
      ).void
    end
    def initialize(pull_request:, viewer:, cap_filter:)
      @pull_request = pull_request
      @viewer = viewer
      @cap_filter = cap_filter
    end

    MAX_LINKED_ISSUES = 10

    sig { returns(DevelopmentData) }
    def load
      issues = pull_request.cap_filtered_close_issue_references_for(
        viewer: viewer,
        cap_filter: cap_filter,
      ).take(MAX_LINKED_ISSUES)

      DevelopmentData.new(
        linked_issues: issues.map { |issue| build_linked_issue(issue) },
      )
    end

    private

    sig { params(issue: ::Issue).returns(LinkedIssueData) }
    def build_linked_issue(issue)
      repository = T.must(issue.repository)
      owner = T.must(repository.owner)

      LinkedIssueData.new(
        id: issue.id,
        number: issue.number,
        title: issue.title,
        url: issue.permalink(include_host: false),
        state: issue.state,
        state_reason: issue.state_reason,
        repository: RepositoryData.new(
          owner: owner.display_login,
          name: repository.name,
        ),
      )
    end
  end
end
