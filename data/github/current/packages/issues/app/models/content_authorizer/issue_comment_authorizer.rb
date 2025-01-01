# typed: true
# frozen_string_literal: true

class ContentAuthorizer::IssueCommentAuthorizer < ContentAuthorizer
  attr_accessor :issue, :repo

  def initialize(actor, operation, data)
    super
    @issue = data[:issue] || GitHub::NullIssue.new
    @repo  = data[:repo]  || GitHub::NullRepository.new
  end

  # Public: All of the authorization errors blocking the given actor from
  # creating or mutating an issue comment. These should be assembled in
  # priority order (from most urgent/important to least) because the API
  # will only return the first error discovered.
  #
  # fail_fast - Bail out after the first failure.
  #
  # Returns an Array of ContentAuthorizationError objects.
  def errors(fail_fast: false)
    ([]).tap do |errors|
      if actor.must_verify_email? && verified_email_required_to?(operation)
        errors << ContentAuthorizationError::EmailVerificationRequired.new
        return errors if fail_fast
      end

      if repo.archived?
        errors << ContentAuthorizationError::RepoArchived.new
        return errors if fail_fast
      end

      staff_is_minimizing = GitHub.context[:staff_minimizing]
      if !staff_is_minimizing && issue.locked_for?(actor)
        errors << ContentAuthorizationError::IssueLocked.new
        return errors if fail_fast
      end

      unless issue.pull_request? || repo.has_issues?
        errors << ContentAuthorizationError::IssuesDisabled.new
        return errors if fail_fast
      end

      if !in_automated_data_transformation? && repo.locked_on_migration?
        errors << ContentAuthorizationError::RepoLocked.new
        return errors if fail_fast
      end

      if issue.over_comment_limit? && operation == :create
        errors << ContentAuthorizationError::IssueOverCommentLimit.new
        return errors if fail_fast
      end
    end
  end
end
