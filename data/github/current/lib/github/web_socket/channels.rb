# typed: true
# frozen_string_literal: true

# Helper methods to generate WebSocket channel names.
module GitHub::WebSocket::Channels
  # All public singleton methods on this module are expected to define a signed variation.

  # Channel that gets updated whenever a branch is created, deleted, or
  # pushed to.
  #
  # repository  - A Repository.
  # branch_name - A String with a ref name (like "master").
  def self.branch(repository, branch_name)
    join("repo", repository.id, "branch", normalize_branch(branch_name))
  end

  def self.signed_branch(repository, branch_name)
    ::GitHub::WebSocket.signed_channel(branch(repository, branch_name))
  end

  # Channel that gets updated whenever someone pushes code to the repo.
  #
  # repository - A Repository.
  # user       - The User who pushed code into `repository`.
  def self.post_receive(repository, user)
    join("repo", repository.id, "post-receive", user.id)
  end

  def self.signed_post_receive(repository, user)
    ::GitHub::WebSocket.signed_channel(post_receive(repository, user))
  end

  # Channel that gets updated whenever stacks instance status changes.
  #
  # stacks_instance_status - stack instance step statuses
  def self.stacks_instance_status(stacks_instance_status)
    join("stacks_instance", stacks_instance_status.instance_id, stacks_instance_status.plan_id)
  end

  def self.signed_stacks_instance_status(stacks_instance_status)
    ::GitHub::WebSocket.signed_channel(self.stacks_instance_status(stacks_instance_status))
  end

  def self.milestone_prioritized(milestone)
    join("milestone", milestone.id, "prioritized")
  end

  def self.signed_milestone_prioritized(milestone)
    ::GitHub::WebSocket.signed_channel(milestone_prioritized(milestone))
  end

  def self.project(project)
    join("projects", project.id)
  end

  def self.signed_project(project)
    ::GitHub::WebSocket.signed_channel(project(project))
  end

  def self.project_metadata(project)
    join("projects", "metadata", project.id)
  end

  def self.signed_project_metadata(project)
    ::GitHub::WebSocket.signed_channel(project_metadata(project))
  end

  def self.project_add_cards_link(project_id)
    join("projects", "add_cards", project_id)
  end

  def self.signed_project_add_cards_link(project_id)
    ::GitHub::WebSocket.signed_channel(project_add_cards_link(project_id))
  end

  def self.project_card(card)
    join("projects", "cards", card.id)
  end

  def self.signed_project_card(card)
    ::GitHub::WebSocket.signed_channel(project_card(card))
  end

  def self.memex(memex)
    join("memex", memex.id)
  end

  def self.signed_memex(memex)
    ::GitHub::WebSocket.signed_channel(self.memex(memex))
  end

  def self.team(team)
    join("teams", team.id)
  end

  def self.signed_team(team)
    ::GitHub::WebSocket.signed_channel(self.team(team))
  end

  def self.discussion_post(post)
    join("discussion_posts", post.id)
  end

  def self.signed_discussion_post(post)
    ::GitHub::WebSocket.signed_channel(discussion_post(post))
  end

  # Channel that gets updated whenever a Discussion is updated,
  # or when reactions or comments are updated for this Discussion.
  #
  # discussion - A Discussion.
  def self.discussion(discussion)
    join("discussion", discussion.id)
  end

  def self.signed_discussion(discussion)
    ::GitHub::WebSocket.signed_channel(self.discussion(discussion))
  end

  # Channel that gets updated whenever a content changes in a discussion that is
  # relevant to the discussion's Copilot summary.
  #
  # discussion - A Discussion.
  def self.discussion_summary(discussion)
    join("discussion_summary", discussion.id)
  end

  def self.signed_discussion_summary(discussion)
    ::GitHub::WebSocket.signed_channel(self.discussion_summary(discussion))
  end

  # Channel that gets updates whenever an item on a Discussion timeline is created.
  #
  # discussion - a Discussion
  def self.discussion_timeline(discussion)
    join("discussion", discussion.id, "timeline")
  end

  def self.signed_discussion_timeline(discussion)
    ::GitHub::WebSocket.signed_channel(self.discussion_timeline(discussion))
  end

  # Channel that is alerted when a thread is marked as read.
  # Messages here will contain individual items that are being
  # marked as read.
  #
  # user - The user for which to open the mark as read channel.
  #
  # Returns String.
  def self.marked_as_read(user)
    join("marked-as-read", user.id)
  end

  def self.signed_marked_as_read(user)
    ::GitHub::WebSocket.signed_channel(marked_as_read(user))
  end

  # Channel that gets updated whenever a new Status is created for a
  # given commit.
  #
  # repository - A Repository.
  # oid        - A Commit's OID, as a String.
  def self.status(repository, oid)
    join("repo", repository.id, "status", oid)
  end

  def self.signed_status(repository, oid)
    ::GitHub::WebSocket.signed_channel(status(repository, oid))
  end

  # Channel that gets updated whenever a new Status is created for a
  # given commit.
  #
  # repository - A Repository.
  # oid        - A Commit's OID, as a String.
  def self.commit(repository, oid)
    join("repo", repository.id, "commit", oid)
  end

  def self.signed_commit(repository, oid)
    ::GitHub::WebSocket.signed_channel(commit(repository, oid))
  end

  # Channel that gets updated whenever an issue gets updated.
  #
  # issue - An issue.
  def self.issue(issue)
    join("issue", issue.id)
  end

  def self.signed_issue(issue)
    ::GitHub::WebSocket.signed_channel(self.issue(issue))
  end

  # Channel that gets updated whenever the issue state changes.
  # issue - An issue.
  def self.issue_state(issue)
    join("issue", issue.id, "state")
  end

  def self.signed_issue_state(issue)
    ::GitHub::WebSocket.signed_channel(issue_state(issue))
  end

  # Channel that gets updates whenever an item on an issue timeline changes.
  #
  # issue - An issue
  def self.issue_timeline(issue)
    join("issue", issue.id, "timeline")
  end

  def self.signed_issue_timeline(issue)
    ::GitHub::WebSocket.signed_channel(issue_timeline(issue))
  end

  # Channel that gets updates whenever an issue_summary is updated.
  #
  # issue_summary - An issue_summary
  def self.issue_summary(issue_summary)
    join("issue_summary", issue_summary.id)
  end

  def self.signed_issue_summary(issue_summary)
    ::GitHub::WebSocket.signed_channel(self.issue_summary(issue_summary))
  end

  # Channel that gets updates whenever an update to particular GraphQL
  # subscription event occurs
  #
  # gql_sub_id - String subscription id
  def self.graphql(gql_sub_id)
    join("graphql", gql_sub_id)
  end

  def self.signed_graphql(gql_sub_id)
    ::GitHub::WebSocket.signed_channel(graphql(gql_sub_id))
  end

  # Channel that gets updates whenever an item is added/removed from close_issue_references.
  #
  # issue - An issue
  def self.close_issue_references(issue)
    join("issue", issue.id, "close_issue_references")
  end

  def self.signed_close_issue_references(issue)
    ::GitHub::WebSocket.signed_channel(close_issue_references(issue))
  end

  # Channel that gets updated whenever a Pull Request is updated, or
  # the head_ref gets pushed to.
  #
  # pr - A PullRequest.
  def self.pull_request(pr)
    join("pull_request", pr.id)
  end

  def self.signed_pull_request(pr)
    ::GitHub::WebSocket.signed_channel(pull_request(pr))
  end

  # Channel that gets updated whenever the pull request state changes.
  #
  # pr - A PullRequest.
  def self.pull_request_state(pr)
    issue_state(pr.issue)
  end

  def self.signed_pull_request_state(pr)
    ::GitHub::WebSocket.signed_channel(pull_request_state(pr))
  end

  # Channel that gets updates whenever an item on a pull request timeline changes.
  #
  # pr - An PullRequest
  def self.pull_request_timeline(pr)
    join("pull_request", pr.id, "timeline")
  end

  def self.signed_pull_request_timeline(pr)
    ::GitHub::WebSocket.signed_channel(pull_request_timeline(pr))
  end

  # Channel that gets updated whenever a pull request's deployment succeeds.
  #
  # pr - A PullRequest
  def self.pull_request_deployed(pr)
    join("pull_request", pr.id, "deployed")
  end

  def self.signed_pull_request_deployed(pr)
    ::GitHub::WebSocket.signed_channel(pull_request_deployed(pr))
  end

  # Channel that gets updated whenever a Pull Request is approved or changes are requested.
  #
  # pr - A PullRequest
  def self.pull_request_review_state(pr)
    join("pull_request", pr.id, "review_state")
  end

  def self.signed_pull_request_review_state(pr)
    ::GitHub::WebSocket.signed_channel(pull_request_review_state(pr))
  end

  # Channel that gets updates whenever a pull request's git merge state is updated.
  #
  # pr - An PullRequest
  def self.pull_request_git_merge_state(pr)
    join("pull_request", pr.id, "git_merge_state")
  end

  def self.signed_pull_request_git_merge_state(pr)
    ::GitHub::WebSocket.signed_channel(pull_request_git_merge_state(pr))
  end

  # Channel that gets updated whenever a Pull Request Review is updated
  #
  # review - A PullRequestReview.
  def self.pull_request_review(review)
    join("pull_request_review", review.id)
  end

  def self.signed_pull_request_review(review)
    ::GitHub::WebSocket.signed_channel(pull_request_review(review))
  end

  # Channel that gets updated whenever the Pre-receive Environment download_state changes.
  #
  # env - A PreReceiveEnvironment.
  def self.pre_receive_environment_state(env)
    join("pre_receive_environment", env.id, "state")
  end

  def self.signed_pre_receive_environment_state(env)
    ::GitHub::WebSocket.signed_channel(pre_receive_environment_state(env))
  end

  # Channel list that gets updated whenever either the PR's head or base
  # branches change, or when the head status changes, so we can check
  # for mergeability.
  #
  # pr - A PullRequest.
  def self.pull_request_mergeable(pr)
    [
      # If the head_repository is nil, this is a cross-repo fork with a deleted head.
      (pr.head_repository ? branch(pr.head_repository, pr.display_head_ref_name) : nil),
      branch(pr.base_repository, pr.display_base_ref_name),
      commit(pr.base_repository, pr.head_sha),
    ].compact
  end

  def self.signed_pull_request_mergeable(pr)
    ::GitHub::WebSocket.signed_channel(pull_request_mergeable(pr))
  end

  # Channel that gets updated whenever an action_required
  # workflow run is updated that belongs to a pull request
  #
  # pr - A PullRequest
  def self.pull_request_workflow_run_state(pr)
    join("pull_request", pr.id, "workflow_run")
  end

  def self.signed_pull_request_workflow_run_state(pr)
    ::GitHub::WebSocket.signed_channel(pull_request_workflow_run_state(pr))
  end

  # Channel that gets updated whenever a pull request's merge queue entry
  # state changes.
  #
  # pr - A PullRequest
  def self.pull_request_merge_queue_entry(pr)
    join("pull_request", pr.id, "merge_queue_entry")
  end

  def self.signed_pull_request_merge_queue_entry(pr)
    ::GitHub::WebSocket.signed_channel(pull_request_merge_queue_entry(pr))
  end

  # Channel that gets updated when a pull request has a MergeQueueEntry
  # and a MergeQueueEntry in the queue has been updated.
  #
  # pr - A PullRequest
  def self.pull_request_merge_queue_entry_state(pr)
    join("pull_request", pr.id, "merge_queue_entry_state")
  end

  def self.signed_pull_request_merge_queue_entry_state(pr)
    ::GitHub::WebSocket.signed_channel(pull_request_merge_queue_entry_state(pr))
  end

  # Channel that gets touched anytime the user's list subscription status
  # changes. For an example, after a user clicks to watch/unwatch a repo.
  #
  # list - A list object (Repository, Team, etc)
  def self.list_subscription(user, list)
    join("list-subscription", subject_id(list), user.id)
  end

  def self.signed_list_subscription(user, list)
    ::GitHub::WebSocket.signed_channel(list_subscription(user, list))
  end

  # Channel that gets touched anytime the user's thread subscription status
  # changes. For an example, after a user clicks to watch a thread or
  # mutes the thread.
  #
  # user      - A User
  # list      - A Repository
  # thread_id - Thread Integer id
  def self.thread_subscription(user, list, thread_id)
    join("thread-subscription", thread_id, user.id)
  end

  def self.signed_thread_subscription(user, list, thread_id)
    ::GitHub::WebSocket.signed_channel(thread_subscription(user, list, thread_id))
  end

  # Channel that gets updated anytime a user notification list is changed.
  # Includes new notifications as well has user marking existing notifications
  # as read.
  #
  # user - A User
  def self.notifications_changed(user)
    join("notification-changed", user.id)
  end

  def self.signed_notifications_changed(user)
    ::GitHub::WebSocket.signed_channel(notifications_changed(user))
  end

  # Channel that gets updated anytime a user notification related to a specific repo/issue is changed.
  #
  # user - A User
  # issue_number - The issue number.
  # repository_name - The repository name.
  def self.notifications_changed_per_issue(user, issue_number, repository_name)
    join("notification-changed", user.id, issue_number, repository_name)
  end

  def self.signed_notifications_changed_per_issue(user, issue_number, repository_name)
    ::GitHub::WebSocket.signed_channel(notifications_changed_per_issue(user, issue_number, repository_name))
  end

  # Channel that gets updated anytime a list is changed.
  # Includes new notifications as well has user marking existing notifications
  # as read.
  #
  # queue - A SpamQueue
  def self.spam_queue_changed(queue)
    join("spam-queue", queue.id)
  end

  def self.signed_spam_queue_changed(queue)
    ::GitHub::WebSocket.signed_channel(spam_queue_changed(queue))
  end

  # Channel that gets updated any time an import has new progress information.
  #
  # repository - A Repository
  def self.source_import(repository)
    join("repository_import", repository.id)
  end

  def self.signed_source_import(repository)
    ::GitHub::WebSocket.signed_channel(source_import(repository))
  end

  def self.check_run(check_run)
    join("check_runs", check_run.id)
  end

  def self.signed_check_run(check_run)
    ::GitHub::WebSocket.signed_channel(self.check_run(check_run))
  end

  def self.check_suite(check_suite)
    join("check_suites", check_suite.id)
  end

  def self.signed_check_suite(check_suite)
    ::GitHub::WebSocket.signed_channel(self.check_suite(check_suite))
  end

  def self.workflow_runs(repository)
    join("workflow_runs", repository.id)
  end

  def self.signed_workflow_runs(repository)
    ::GitHub::WebSocket.signed_channel(workflow_runs(repository))
  end

  def self.workflow_job_run(run_id, parent_job_id)
    join("workflow_job", run_id, parent_job_id)
  end

  def self.signed_workflow_job_run(run_id, parent_job_id)
    ::GitHub::WebSocket.signed_channel(workflow_job_run(run_id, parent_job_id))
  end

  def self.actions_approval_logs(workflow_run)
    join("workflow_run", workflow_run.id, "approval-log")
  end

  def self.signed_actions_approval_logs(workflow_run)
    ::GitHub::WebSocket.signed_channel(actions_approval_logs(workflow_run))
  end

  def self.actions_results_channel(workflow_run_backend_id, workflow_job_run_backend_id)
    join("actions_results", workflow_run_backend_id, workflow_job_run_backend_id)
  end

  def self.signed_actions_results_channel(workflow_run_backend_id, workflow_job_run_backend_id)
    ::GitHub::WebSocket.signed_channel(actions_results_channel(workflow_run_backend_id, workflow_job_run_backend_id))
  end

  def self.actions_artifacts(workflow_run)
    join("workflow_run", workflow_run.id, "artifacts")
  end

  def self.signed_actions_artifacts(workflow_run)
    ::GitHub::WebSocket.signed_channel(actions_artifacts(workflow_run))
  end

  def self.deployments_dashboard_environment(repository, environment)
    join("deployments_dashboard", repository.id, environment)
  end

  def self.signed_deployments_dashboard_environment(repository, environment)
    ::GitHub::WebSocket.signed_channel(deployments_dashboard_environment(repository, environment))
  end

  def self.actions_gate_requests(workflow_run)
    join("workflow_run", workflow_run.id, "gate-requests")
  end

  def self.signed_actions_gate_requests(workflow_run)
    ::GitHub::WebSocket.signed_channel(actions_gate_requests(workflow_run))
  end

  def self.packages_migration(migration_run_id)
    join("packages_migration", migration_run_id)
  end

  def self.signed_packages_migration(migration_run_id)
    ::GitHub::WebSocket.signed_channel(packages_migration(migration_run_id))
  end

  # Channel that gets updated when a new workflow run is triggered for the prebuild configuration
  # or the workflow run switches to a new status
  def self.prebuild_configuration_workflow_run(prebuild_configuration)
    join("prebuild_configuration", prebuild_configuration.id, "workflow_run")
  end

  def self.signed_prebuild_configuration_workflow_run(prebuild_configuration)
    ::GitHub::WebSocket.signed_channel(prebuild_configuration_workflow_run(prebuild_configuration))
  end

  # Channel that gets updated when a workflow run switches
  # to a new execution on re-run
  def self.actions_execution_channel(workflow_run)
    join("workflow_run", workflow_run.id, "execution")
  end

  def self.signed_actions_execution_channel(workflow_run)
    ::GitHub::WebSocket.signed_channel(actions_execution_channel(workflow_run))
  end

  # Channel that gets updated whenever a RepositoryAdvisory
  # gets updated.
  #
  # advisory - A RepositoryAdvisory.
  def self.repository_advisory(advisory)
    join("repository_advisory", advisory.id)
  end

  def self.signed_repository_advisory(advisory)
    ::GitHub::WebSocket.signed_channel(repository_advisory(advisory))
  end

  # Channel that gets updated for events related to the given user are of
  # interest for GitHub Desktop.
  #
  # user - A User.
  def self.desktop_user(user)
    join("desktop", "user", user.id)
  end

  def self.signed_desktop_user(user)
    ::GitHub::WebSocket.signed_channel(desktop_user(user))
  end

  # Channel that gets updated whenever a BulkDmcaTakedown status is updated
  #
  #  # takedown  - A Stafftools::BulkDmcaTakedown
  def self.bulk_takedown_status(takedown)
    join("bulk_takedown_status", takedown.id)
  end

  def self.signed_bulk_takedown_status(takedown)
    ::GitHub::WebSocket.signed_channel(bulk_takedown_status(takedown))
  end

  # Channel that gets updated whenever GitHub app is installed on a target or when
  # repositories are added to an installation.
  #
  # target - Installation target.
  def self.integration_installation(target)
    join("integration_installation", target.id)
  end

  def self.signed_integration_installation(target)
    ::GitHub::WebSocket.signed_channel(integration_installation(target))
  end

  def self.merge_queue(merge_queue)
    join("merge_queue", merge_queue.id)
  end

  def self.signed_merge_queue(merge_queue)
    ::GitHub::WebSocket.signed_channel(merge_queue(merge_queue))
  end

  # Channel that gets updated when the status of a dry run for a
  # secret scanning custom pattern is updated.
  def self.custom_pattern_dry_run_status(owner)
    join("custom_pattern_dry_run_status", owner.id)
  end

  def self.signed_custom_pattern_dry_run_status(owner)
    ::GitHub::WebSocket.signed_channel(custom_pattern_dry_run_status(owner))
  end

  # Channel that communicates when a user's codespace on
  # a repository has been created or deleted.
  def self.repository_codespaces(repository, user)
    join("repository_codespaces", repository.id, user.id)
  end

  def self.signed_repository_codespaces(repository, user)
    ::GitHub::WebSocket.signed_channel(repository_codespaces(repository, user))
  end

  def self.business_report_export_status(export)
    join("business_report_export_status", export.id)
  end

  def self.signed_business_report_export_status(export)
    ::GitHub::WebSocket.signed_channel(business_report_export_status(export))
  end

  def self.security_configurations_update(owner)
    join("security_configurations", owner.class, owner.id)
  end

  def self.signed_security_configurations_update(owner)
    ::GitHub::WebSocket.signed_channel(security_configurations_update(owner))
  end

  # Constructing a channel name is handled by AliveSubscriptions, we just use
  # this for the def_signed macro.
  def self.graphql_subscription(channel_name:)
    channel_name
  end

  def self.signed_graphql_subscription(channel_name:)
    ::GitHub::WebSocket.signed_channel(channel_name)
  end

  def self.setting_orchestration_status(orchestration)
    join("setting_orchestration", orchestration.id)
  end

  def self.signed_setting_orchestration_status(orchestration)
    ::GitHub::WebSocket.signed_channel(setting_orchestration_status(orchestration))
  end

  # Channel that gets updated for events related to a code scanning alert.
  #
  # alert_number - The (logical) alert number from Turboscan.
  def self.code_scanning_alert(repository, alert_number:)
    join("repo", repository.id, "code_scanning_alert", alert_number.to_s)
  end

  def self.signed_code_scanning_alert(repository, alert_number:)
    ::GitHub::WebSocket.signed_channel(code_scanning_alert(repository, alert_number:))
  end

  # Internal: Generate a String name out of parts consistently.
  def self.join(*args)
    args.join(":")
  end
  private_class_method :join

  # Internal: Normalize different representations of git branch names
  def self.normalize_branch(branch_name)
    branch_name.sub(%r{^refs/heads/}, "")
  end
  private_class_method :normalize_branch

  def self.subject_id(subject)
    join(subject.class.name.underscore.dasherize, subject.id)
  end
  private_class_method :subject_id
end
