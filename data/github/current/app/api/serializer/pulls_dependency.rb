# typed: true
# frozen_string_literal: true

module Api::Serializer::PullsDependency
  extend T::Helpers

  requires_ancestor { T.class_of(Api::Serializer) }

  class InvalidIssueAssociation < RuntimeError ; end

  # Creates a Hash to be serialized to JSON.
  #
  # pull    - PullRequest instance
  # options - Hash
  #           :full                 - Boolean specifying we want the extended output.
  #           :private              - Boolean specifying we want the private output.
  #           :hook                 - Boolean specifying if called from webhooks
  #           :repo_identifier_only - Boolean specifying the level of detail for serialized repos.
  #
  # Returns a Hash if the org exists, or nil.
  def pull_request_hash(pull, options = {})
    return nil if !pull

    options = Api::SerializerOptions.from(options)

    repo       = repo_path(options, pull)
    pull_url   = url("/repos/#{repo}/pulls/#{pull.number}", options)
    issue_url  = url("/repos/#{repo}/issues/#{pull.number}", options)
    status_url = url("/repos/#{repo}/statuses/#{pull.head_sha}", options)
    review_comment_url = url("/repos/#{repo}/pulls/comments{/number}", options)

    # Add tracing to help debug PRs being created without issues,
    # see #40102 for more details.
    if pull.updated_at.nil? || pull.issue.nil? || pull.issue.updated_at.nil?
      error = InvalidIssueAssociation.new("Invalid PullRequest/Issue association")
      extra = {
        "gh.pull_request.id": pull.id,
        "gh.pull_request.valid": pull.valid?,
        "gh.pull_request.saved": pull.persisted?,
        "gh.issue.id": pull.issue.id
      }
      Failbot.push_sensitive("gh.pull_request.errors": pull.errors.full_messages.to_sentence)
      if issue = pull.issue
        extra.merge!({
          "gh.issue.valid": issue.valid?,
          "gh.issue.saved": issue.persisted?
        })
        Failbot.push_sensitive("gh.issue.errors": issue.errors.full_messages.to_sentence)
      end
      Failbot.report_trace(error, extra)
    end

    requested_user_reviewers, requested_team_reviewers = requested_user_and_team_reviewers(pull)

    updated_at = if pull.updated_at > pull.issue.updated_at
      time(pull.updated_at)
    else
      time(pull.issue.updated_at)
    end
    hash       = {
      url: pull_url,
      id: pull.id,
      node_id: global_id_for(pull, options),
      html_url: pull.url,
      diff_url: "#{pull.url}.diff",
      patch_url: "#{pull.url}.patch",
      issue_url: issue_url,
      number: pull.number,
      state: pull.issue.state,
      locked: pull.issue.locked?,
      title: pull.title,
      user: user_hash(pull.safe_user, content_options(options)),
      body: pull.body,
      created_at: time(pull.created_at),
      updated_at: updated_at,
      closed_at: time(pull.closed_at),
      merged_at: time(pull.merged_at),
      merge_commit_sha: pull.merge_commit_sha, # DEPRECATED: Will be
      # removed in API v4.
      assignee: user_hash(pull.issue.assignee, content_options(options)),
      assignees: pull.issue.assignees.map { |assignee| simple_user_hash(assignee, content_options(options)) },
      requested_reviewers: requested_user_reviewers.map { |user| simple_user_hash(user, content_options(options)) },
      requested_teams: requested_teams(requested_team_reviewers, options),
      labels: pull.issue.labels.map { |l| label_hash(l, options.merge(repo: repo)) },
      milestone: milestone_hash(pull.issue.milestone, options.merge(repo: repo)),
      draft: pull.draft?,
      commits_url: pull_url + "/commits",
      review_comments_url: pull_url + "/comments",
      review_comment_url: review_comment_url,
      comments_url: issue_url + "/comments",
      statuses_url: status_url,
      head: {
        label: pull.head_label(username_qualified: true),
        ref: pull.head_ref_name,
        sha: pull.head_sha,
        user: user_hash(pull.head_user, content_options(options)),
        repo: if options[:repo_identifier_only]
                repository_identifier_hash(pull.head_repository, options_for_repo_hash(options))
              else
                repository_hash(pull.head_repository, options_for_repo_hash(options))
              end,
      },
      base: {
        label: pull.base_label(username_qualified: true),
        ref: pull.base_ref_name,
        sha: pull.base_sha,
        user: user_hash(pull.base_user, content_options(options)),
        repo: if options[:repo_identifier_only]
                repository_identifier_hash(pull.base_repository, options_for_repo_hash(options))
              else
                repository_hash(pull.base_repository, options_for_repo_hash(options))
              end,
      },
      _links: {
        self: { href: pull_url },
        html: { href: pull.url },
        issue: { href: issue_url },
        comments: { href: issue_url + "/comments" },
        review_comments: { href: pull_url + "/comments" },
        review_comment: { href: review_comment_url },
        commits: { href: pull_url + "/commits" },
        statuses: { href: status_url },
      },
      author_association: pull.author_association_symbol(options[:current_user]).to_s.upcase,
      auto_merge: if pull.auto_merge_request.present?
                    {
                      enabled_by: user_hash(pull.auto_merge_request.user, content_options(options)),
                      merge_method: pull.auto_merge_request.minimal_merge_method,
                      commit_title: pull.auto_merge_request.commit_title,
                      commit_message: pull.auto_merge_request.commit_message,
                    }
                  else
                    nil
                  end,
    }.update(mime_body_hash(pull, options))

    hash[:active_lock_reason] = pull.active_lock_reason

    if options[:full]
      hash.update({
        merged: pull.merged?,
        mergeable: pull.currently_mergeable?,
        rebaseable: pull.currently_mergeable? && pull.rebase_safe?,
        mergeable_state: pull.merge_state(viewer: options[:current_user]).status,
        merged_by: user_hash(pull.merged_by, content_options(options)),
        comments: comments_count(pull, options[:current_user]),
        review_comments: pull.review_comments.count,
        maintainer_can_modify: pull.fork_collab_granted?,
      })

      hash.update pull_request_diff_stats_hash(pull)
    end

    if options.accepts_semantic_version?("night-shift")
      merge_state = pull.merge_state(viewer: options[:current_user])
      decision = merge_state.pull_request_review_policy_decision
      hash.update(
        mergeability_requirements: {
          required_reviews: {
            fulfilled: decision.rules_fulfilled,
            summary: decision.reason.summary,
            message: decision.reason.message,
          },
        },
      )
    end

    hash
  end

  def minimal_pull_request_hash(pull, options = {})
    return nil if !pull

    options = Api::SerializerOptions.from(options)

    {}.tap do |h|
      h[:url] = url("/repos/#{pull.repository.name_with_owner_for_api(use: options[:serialize_login])}/pulls/#{pull.number}", options)
      h[:id]  = pull.id
      h[:number] = pull.number
      h[:head] = {
        ref: pull.head_ref_name,
        sha: pull.head_sha,
        repo: {
          id:   pull.head_repository&.id,
          url:  url("/repos/#{pull.head_repository&.name_with_owner_for_api(use: options[:serialize_login])}", options),
          name: pull.head_repository&.name,
        },
      }
      h[:base] = {
        ref: pull.base_ref_name,
        sha: pull.base_sha,
        repo: {
          id:   pull.base_repository&.id,
          url:  url("/repos/#{pull.base_repository&.name_with_owner_for_api(use: options[:serialize_login])}", options),
          name: pull.base_repository&.name,
        },
      }
    end
  end

  private

  # Returns the pending requested user and team reviewers as an array of arrays.
  #
  # pull - the pull request.
  #
  # Returns an array of arrays, where the first element is an array of users and the second element is an array of teams.
  def requested_user_and_team_reviewers(pull)

    # We want to introspect the pull request to validate that the review_requests_pending and review
    # associations have been loaded. We consider this true if the review_requests_pending association is loaded and
    # the first review_request is empty or the review request is present with the reviewer association loaded.
    preloaded_user_and_team_reviewers = (
      pull.association(:review_requests_pending).loaded? &&
      (pull.review_requests_pending.empty? || pull.review_requests_pending.first&.association(:reviewer)&.loaded?)
    )

    if preloaded_user_and_team_reviewers
      reviewers_by_type = pull.review_requests_pending.map(&:reviewer).group_by(&:class)
      requested_user_reviewers = reviewers_by_type.fetch(User, [])
      requested_team_reviewers = reviewers_by_type.fetch(Team, [])
    else
      requested_user_reviewers = pull.review_requests.pending.users
      requested_team_reviewers = pull.review_requests.pending.teams
    end

    [requested_user_reviewers, requested_team_reviewers]
  end

  def pull_request_diff_stats_hash(pull)
    GitHub.tracer.in_span("Api::Serializer::PullsDependency#pull_request_diff_stats_hash") do
      total_commits = 0
      additions     = 0
      deletions     = 0
      changed_files = 0

      if pull.historical_comparison.valid?
        begin
          total_commits, additions, deletions, changed_files = Promise.all([
            pull.async_total_commits,
            pull.async_additions,
            pull.async_deletions,
            pull.async_changed_files
          ]).sync
        rescue GitRPC::CommandFailed, Repository::CommandFailed => boom
          Failbot.report boom, app: "github-user"
          GitHub.logger.warn("Rescue GitRPC::CommandFailed, Repository::CommandFailed", {
            "code.namespace": "Api::Serializer::PullsDependency",
            "code.function": "pull_request_diff_stats_control",
            "exception": boom,
            "error_type": "#{boom.class.name}",
          })
        end
      else
        GitHub.logger.warn("Invalid pull.historical_comparison or rescued object missing", {
          "code.namespace": "Api::Serializer::PullsDependency",
          "code.function": "pull_request_diff_stats_control",
          "gh.pull.id": pull.id,
          "gh.issue.id": pull.issue.id,
        })
      end

      {
        commits: total_commits,
        additions: additions,
        deletions: deletions,
        changed_files: changed_files,
      }
    end
  end

  def options_for_repo_hash(options)
    return options if options[:hook]
    content_options(options)
  end

  def requested_teams(teams, options)
    teams.map do |team|
      current_user = options[:current_user]
      team_hash_options = content_options(options)

      if !(current_user && team.visible_to?(current_user))
        team_hash_options[:exclude_parent] = true
      end

      team_hash(team, team_hash_options)
    end
  end

  def comments_count(pull, current_user)
    return 0 if pull.repository.spammy?

    pull.issue.comments.filter_spam_for(current_user).count
  end
end
