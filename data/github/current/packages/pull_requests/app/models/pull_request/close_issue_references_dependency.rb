# typed: true
# frozen_string_literal: true

module PullRequest::CloseIssueReferencesDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { PullRequest }

  included do
    T.bind(self, T.class_of(ActiveRecord::Base))
    # Public: Get PullRequests that indicate they close the given Issue.
    #
    # issue  - an Integer Issue ID or an Issue
    # author - filter PullRequests by their author; a User
    #
    # Returns a PullRequest relation.
    scope :closes, ->(issue, author) do
      closing_pr_ids = CloseIssueReference.closes(issue).by_user(author).pluck(:pull_request_id)
      where(id: closing_pr_ids, user_id: author)
    end
  end

  def close_issues_on_merge(actor)
    return unless close_issues_on_merge_permitted?

    xrefed_issues = closable_issues

    # find all manually referenced close issues
    manual_issues = close_issue_references.manual.map(&:issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    ActiveRecord::Base.connected_to(role: :writing) do
      (xrefed_issues + manual_issues).each do |i|
        auto_close_allowed = AutoCloseIssuesConfig.new(i.repository).auto_close_allowed?
        next unless auto_close_allowed
        next if cross_repo_close_blocked?(i, actor)

        Issues.domain.update_state(i, Issues::State::Closed, actor, attributes: { pr: T.must(issue).id })
      end
      log_issue_close_status_on_merge(actor&.id)
    end
  end

  # Internal: The issues to close when this PR is accepted
  #
  # All issue references from the filter result that respond truthily
  # to `close?`. See GitHub::HTML::IssueMentionFilter for more info.
  #
  # Returns an Array of Issues
  # Returns an empty Array when the base ref is not the default branch
  def closable_issues
    @closable_issues ||= calculate_close_issues
  end

  def calculate_close_issues(user: nil)
    # don't create close issues if closing isn't permitted
    return [] unless close_issues_on_merge_permitted?
    return [] unless body =~ GitHub::HTML::IssueMentionFilter::MARKER

    result = if user
      potential_close_issues_for_user(user)
    else
      calculate_filter_result
    end

    (result.issues || []).select(&:close?).collect(&:issue)
  end

  # Internal: Whether the PR is permitted to close linked issues when merged
  def close_issues_on_merge_permitted?
    return false if !repository

    effective_base = if stacks_close_issue_references_patch_enabled?
      stack_or_pull_base_ref_name
    else
      base_ref_name
    end

    effective_base == T.must(repository).default_branch
  end

  def cap_filtered_close_issue_references_for(viewer:, user_linked_only: false, cap_filter:)
    async_cap_filtered_close_issue_references_for(
      viewer: viewer,
      user_linked_only: user_linked_only,
      cap_filter: cap_filter
    ).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def async_cap_filtered_close_issue_references_for(viewer:, user_linked_only: false, cap_filter:)
    async_close_issue_references.then do |references|
      issue_ids = if user_linked_only
        references.select { |ref| ref.source == "manual" }.pluck(:issue_id).compact
      else
        references.pluck(:issue_id).compact
      end
      Platform::Loaders::ActiveRecord.load_all(::Issue, issue_ids).then do |issues|
        # Use security_violation_behaviour: :nil to prevent loading any repos
        # the viewer doesn't have access to see
        authorized_issues = cap_filter.authorized_resources(issues.compact)

        accessible_issues = authorized_issues.map do |issue|
          next if !issue
          Promise.all([issue.async_repository, issue.async_user]).then do |repo, _user|
            next if !repo
            next if (issue.spammy? || repo.spammy?) && !viewer&.site_admin?
            readable_promise = repo.public? ? Promise.resolve(true) : issue.async_readable_by?(viewer)
            readable_promise.then do |readable|
              next unless readable
              next if issue.pull_request?
              issue
            end
          end
        end

        Promise.all(accessible_issues).then do |accessible_issues|
          accessible_issues.compact
        end
      end
    end
  end

  private

  # Internal: Whether the per-repo flag that lets stacked PRs auto-close issues
  # via Closes/Fixes keywords (using the stack base instead of the immediate
  # base ref) is enabled.
  def stacks_close_issue_references_patch_enabled?
    FeatureFlag.vexi.enabled?(:pull_request_stacks_close_issue_references, repository, default: false)
  end

  # Internal: The result from the BodyContent filter processing
  #
  # Returns a BodyContent Result struct
  def filter_result
    @filter_result ||= filter_content.result
  end

  def calculate_filter_result
    @filter_result = calculate_filter_content.result
  end

  # Internal: The BodyContent, processed for issue-close references
  #
  # Returns a BodyContent object
  def filter_content
    @filter_content ||= calculate_filter_content
  end

  def calculate_filter_content
    @filter_content = GitHub::HTML::BodyContent.new(body, filter_context,
                                                    GitHub::Goomba::MarkdownPipeline)
  end

  # Internal: Similar to #calculate_filter_content, filters the PR issue body
  # for closing issue references using closing keywords.
  # Filter is based on provided user. Used to calculate potential keywords
  # prior to merging PR.
  #
  # Returns a BodyContent Result struct
  def potential_close_issues_for_user(user)
    context = filter_context.dup
    context[:current_user] = user
    GitHub::HTML::BodyContent.new(body, context, GitHub::Goomba::MarkdownPipeline).result
  end

  # Internal: The context hash to use for processing the PR for issue-close references
  #
  # Returns a Hash with :repository and :current_user keys
  def filter_context
    {
      entity: entity,
      current_user: close_issue_references_filter_current_user,
      location: self.class.name,
    }
  end

  # Internal: The actor that will be passed to the markdown pipeline
  # to extract issue references.
  #
  # Returns a User or Bot or nil.
  def close_issue_references_filter_current_user
    return @close_issue_references_filter_current_user if defined?(@close_issue_references_filter_current_user)

    @close_issue_references_filter_current_user = merged_by

    if @close_issue_references_filter_current_user&.bot?
      @close_issue_references_filter_current_user.async_load_installation_for(repository).sync
    end

    @close_issue_references_filter_current_user
  end

  # Internal: Logs whether issues that should have been closed on merge actually closed
  def log_issue_close_status_on_merge(closing_actor_user_id)
    pr_id = self.id
    log_issues = map_xrefs_to_successful_closing_issue_log_list
    issues_closed, issues_failed_to_close = log_issues.partition { |issue| issue[:state] == "closed" }

    log_payload = {
      "gh.actor.id": closing_actor_user_id,
      "gh.repo.id": repository_id,
      "gh.pull_request.id": pr_id,
      "gh.pull_request.issues_closed_count": issues_closed.length,
      "gh.pull_request.issues_failed_to_close_count": issues_failed_to_close.length,
      "gh.pull_request.issues_closed": issues_closed,
      "gh.pull_request.issues_failed_to_close": issues_failed_to_close,
    }

    GitHub.logger.info(log_payload)
  end

  # Internal: Whether a cross-repo close should be blocked because the actor
  # lacks sufficient permission on the target issue's repository.
  #
  # For same-repo references, this always returns false (no additional check).
  # For cross-repo references, the actor must have push access to the target
  # repo — matching GitHub's documented requirement of "push access" for
  # cross-repository closing. This prevents issue authors from auto-closing
  # their own issues via a PR merge in an unrelated repository.
  #
  # issue - the Issue that would be closed
  # actor - the User who merged the PR
  #
  # Returns Boolean
  def cross_repo_close_blocked?(issue, actor)
    return false if issue.repository_id == repository_id

    issue_repo = issue.repository
    unless issue_repo
      log_cross_repo_close_blocked(issue, actor, reason: "missing_issue_repository")
      return true
    end

    return false unless FeatureFlag.vexi.enabled?(
      :issues_require_write_access_for_cross_repo_close,
      issue_repo,
      default: false
    )

    # Bots (GitHub Apps) require explicit installation with granted
    # permissions — they aren't subject to the issue-author loophole that
    # affects human users, so skip the guard for bot actors.
    if actor&.bot?
      return false
    end

    has_access = actor && issue_repo.pushable_by?(actor)

    unless has_access
      reason = actor ? "actor_lacks_push_access" : "nil_actor"
      log_cross_repo_close_blocked(issue, actor, reason: reason)
    end

    !has_access
  end

  def log_cross_repo_close_blocked(issue, actor, reason:)
    GitHub.logger.info({
      message: "cross_repo_close_blocked",
      reason: reason,
      "gh.actor.id": actor&.id,
      "gh.actor.type": actor&.class&.name,
      "gh.pull_request.id": self.id,
      "gh.pull_request.repo.id": repository_id,
      "gh.issue.id": issue.id,
      "gh.issue.repo.id": issue.repository_id,
    })
  end

  def map_xrefs_to_successful_closing_issue_log_list
    close_issue_references
      .select(&:issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      .map do |xref|
        issue = T.must(xref.issue)
        {
          issue_id: issue.id,
          issue_repo_id: issue.repository_id,
          issue_author_id: issue.user_id,
          xref_id: xref.id,
          xref_creator_id: xref.actor_id,
          xref_source: xref.source,
          state: issue.state,
        }
      end
  end
end
