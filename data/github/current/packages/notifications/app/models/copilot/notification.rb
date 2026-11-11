# typed: true
# frozen_string_literal: true

module Copilot
  # A lightweight wrapper around a notification that includes Copilot-specific attributes.
  # This allows us to hydrate notifications with Copilot recommendations and summaries
  # without modifying the underlying notification object.
  class Notification
    attr_reader :notification, :user
    attr_accessor :recommendation, :summary, :ctas, :priority, :subject_data, :metadata

    # Delegate all methods to the underlying notification so this acts as a transparent wrapper
    delegate_missing_to :notification

    CTAS = [
      "Review pull request",
      "Close pull request",
      "Merge pull request",
      "Reopen pull request",
      "Ready for review",
      "Assign reviewers",
      "Add assignees",
      "Close Issue",
      "Reopen Issue",
      "Reply to discussion",
      "Add a comment",
      "View checks",
      "View latest comments"
    ]

    def initialize(notification:, user: nil, recommendation: nil, summary: nil, ctas: [], priority: 0)
      @notification = notification
      @user = user
      @recommendation = recommendation
      @summary = summary
      @ctas = ctas
      @priority = priority
      @subject_data = build_subject_data
      @metadata = {}
    end

    # Returns true if this notification has Copilot attributes populated
    def hydrated?
      recommendation.present? || ctas.any?
    end

    # Returns the URL for a given CTA based on the notification's subject
    # @param cta [String] One of the CTAs from the CTAS constant
    # @return [String, nil] The URL path for the CTA, or nil if it cannot be determined
    def cta_url(cta)
      return nil unless CTAS.include?(cta)
      return nil unless subject_data.present?

      repository = notification.list
      return nil unless repository.is_a?(Repository)

      owner_login = repository.owner_display_login
      repo_name = repository.name
      number = subject_data[:number]
      subject_type = subject_data[:type]

      return nil unless number.present?

      case cta
      when "Review pull request"
        # Go to the changes/files page for the PR
        pull_request_changes_url(owner_login, repo_name, number) if pull_request?(subject_type)
      when "View checks"
        # Go to the checks page for the PR
        pull_request_checks_url(owner_login, repo_name, number) if pull_request?(subject_type)
      when "Close pull request", "Merge pull request", "Reopen pull request", "Ready for review"
        # Go to the pull request page
        pull_request_url(owner_login, repo_name, number) if pull_request?(subject_type)
      when "Assign reviewers"
        # Go to the pull request page with reviewers anchor
        pull_request_url_with_reviewers_anchor(owner_login, repo_name, number) if pull_request?(subject_type)
      when "Add assignees", "Close Issue", "Reopen Issue"
        # Go to the issue page
        issue_url(owner_login, repo_name, number) if issue?(subject_type)
      when "Reply to discussion"
        # Go to the discussion page with new_comment_field anchor
        discussion_url_with_comment_anchor(owner_login, repo_name, number) if discussion?(subject_type)
      when "Add a comment", "View latest comments"
        # Go to the subject page (works for issues, PRs, discussions)
        subject_url(owner_login, repo_name, number, subject_type)
      end
    end

    private

    def pull_request?(subject_type)
      subject_type == "PullRequest"
    end

    def issue?(subject_type)
      subject_type == "Issue"
    end

    def discussion?(subject_type)
      subject_type == "Discussion"
    end

    def pull_request_changes_url(owner_login, repo_name, number)
      UrlHelpers.pull_request_changes_path(owner_login, repo_name, number)
    end

    def pull_request_checks_url(owner_login, repo_name, number)
      UrlHelpers.pull_request_checks_path(owner_login, repo_name, number)
    end

    def pull_request_url(owner_login, repo_name, number)
      UrlHelpers.show_pull_request_path(owner_login, repo_name, number)
    end

    def pull_request_url_with_reviewers_anchor(owner_login, repo_name, number)
      "#{UrlHelpers.show_pull_request_path(owner_login, repo_name, number)}#reviewers-select-menu"
    end

    def issue_url(owner_login, repo_name, number)
      UrlHelpers.issue_path(owner_login, repo_name, number)
    end

    def discussion_url_with_comment_anchor(owner_login, repo_name, number)
      "#{UrlHelpers.discussion_path(owner_login, repo_name, number: number)}#new_comment_field"
    end

    def subject_url(owner_login, repo_name, number, subject_type)
      case subject_type
      when "PullRequest"
        pull_request_url(owner_login, repo_name, number)
      when "Issue"
        issue_url(owner_login, repo_name, number)
      when "Discussion"
        discussion_url_with_comment_anchor(owner_login, repo_name, number)
      end
    end

    # This method builds a hash of relevant data about the notification's subject (PR, Issue, etc.)
    # which is sent to CAPI and is used in the UI to show relevant metadata.
    def build_subject_data
      subject = notification.subject
      return {} unless subject.present?

      data = {
        type: subject.class.name,
      }

      case subject
      when Issue
        data.merge!(
          number: subject.number,
          state: subject.state,
          labels: subject.labels.map(&:name),
          author: subject.user&.display_login,
          assignees: subject.assignees.map(&:display_login),
          comments_count: subject.issue_comments_count,
          has_pull_request: subject.pull_request?,
          pull_request_state: subject.pull_request&.state&.to_s,
          pull_request_in_draft: subject.pull_request&.draft_or_in_progress?
        )
      when PullRequest
        reviewers = subject.review_requests.filter_map do |rr|
          reviewer = rr.reviewer
          next if reviewer.nil?
          reviewer.is_a?(Team) ? reviewer.combined_slug : reviewer.display_login
        end

        data.merge!(
          number: subject.number,
          state: subject.state,
          draft: subject.draft?,
          mergeable: subject.mergeable?,
          in_merge_queue: subject.in_merge_queue?,
          review_decision: user.present? ? subject.review_decision(viewer: user)&.to_s : nil,
          labels: subject.labels.map(&:name),
          author: subject.user&.display_login,
          assignees: subject.assignees.map(&:display_login),
          reviewers: reviewers,
          is_direct_reviewer: user.present? ? reviewers.include?(user.display_login) : false,
          additions: subject.additions,
          deletions: subject.deletions,
          latest_checks_status: subject.status_at_commit(subject.head_sha)&.state,
        )
      when Discussion
        data.merge!(
          number: subject.number,
          answered: subject.answered?,
          state: subject.state&.to_s,
          state_reason: subject.state_reason&.to_s,
          category: subject.category&.name,
          author: subject.user&.display_login,
        )
      when Release
        data.merge!(
          tag_name: subject.tag_name,
          prerelease: subject.prerelease?,
          draft: subject.draft?,
        )
      when CheckSuite
        data.merge!(
          conclusion: subject.conclusion,
          workflow_name: subject.workflow_name,
        )
      when Actions::WorkflowRun
        data.merge!(
          conclusion: subject.conclusion,
          workflow_name: subject.workflow&.name,
          run_number: subject.run_number,
        )
      when RepositoryVulnerabilityAlert
        data.merge!(
          severity: subject.severity,
        )
      when SecurityAdvisory, RepositoryAdvisory
        data.merge!(
          ghsa_id: subject.ghsa_id,
          severity: subject.severity,
        )
      end

      data
    end
  end
end
