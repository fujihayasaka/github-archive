# typed: true
# frozen_string_literal: true

module UI
  class DataContext
    attr_reader :context

    # This file contains helpers to form a DataContext hash to be passed into UI form elements.
    # The content of this file will be *globally* cached and so nothing it returns should be mutable (e.g. titles, updated at dates, etc) or user specific.
    # Valid things to return include IDs and Created At Timestamps

    def initialize(context)
      @context = context
    end

    def data
      {
        "github" => {
          "organization" => organization_hash(organization),
          "discussion" => discussion_hash(discussion),
          "issue" => issue_hash(issue),
          "pull_request" => pull_request_hash(pull_request),
          "repository" => repository_hash(repository)
        }.compact
      }
    end

    private

    def organization_hash(organization)
      return unless organization
      { "id" => organization.id }
    end

    def discussion_hash(discussion)
      return unless discussion
      { "id" => discussion.id }
    end

    def issue_hash(issue)
      return unless issue
      { "id" => issue.id }
    end

    def pull_request_hash(pull_request)
      return unless pull_request
      { "id" => pull_request.id }
    end

    def repository_hash(repository)
      return unless repository
      { "id" => repository.id }
    end

    def repository
      return context[:entity] if context[:entity].kind_of?(Repository)
      nil
    end

    def organization
      return context[:organization] if context[:organization].kind_of?(Organization)
      nil
    end

    # subject: Discussion, DiscussionComment
    def discussion
      return @discussion if defined?(@discussion)

      @discussion = if context[:subject].kind_of?(Discussion)
        context[:subject]
      elsif context[:subject].respond_to?(:discussion)
        context[:subject].discussion
      end
    end

    # subject: Issue, IssueComment, PullRequest, PullRequestReview, PullRequestReviewComment
    def issue
      return @issue if defined?(@issue)

      @issue = if context[:subject].kind_of?(Issue)
        context[:subject]
      elsif context[:subject].respond_to?(:issue)
        context[:subject].issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      elsif context[:subject].respond_to?(:pull_request)
        context[:subject].pull_request&.issue
      end
    end

    # subject: Issue, IssueComment, PullRequest, PullRequestReview, PullRequestReviewComment
    def pull_request
      return @pull_request if defined?(@pull_request)

      @pull_request = if context[:subject].kind_of?(PullRequest)
        context[:subject]
      elsif context[:subject].respond_to?(:pull_request)
        context[:subject].pull_request
      elsif context[:subject].respond_to?(:issue)
        context[:subject].issue&.pull_request
      end
    end
  end
end
