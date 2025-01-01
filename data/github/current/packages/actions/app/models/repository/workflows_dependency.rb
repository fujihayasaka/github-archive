# typed: true
# frozen_string_literal: true

# actions-specific functionality for repositories
module Repository::WorkflowsDependency
  extend T::Helpers

  requires_ancestor { Repository }

  # this list should match or be a subset of Launch's flowevents.eventTypesForDefaultBranch list. https://github.com/github/launch/blob/1585f31af7350afae208eee3d3f74228a52ef3ea/flow/flowevents/extraction.go#L16
  DEFAULT_BRANCH_EVENTS = Set.new(%w{branch_protection_rule check_run check_suite delete discussion discussion_comment fork gollum issue_comment issues label milestone page_build project project_card project_column public repository_dispatch status watch workflow_run}).freeze
  NON_DEFAULT_BRANCH_EVENTS = Set.new(%w{create deployment deployment_status merge_group pull_request pull_request_review pull_request_review_comment push registry_package release workflow_dispatch}).freeze
  # NON_STANDARD_EVENTS = %w{schedule pull_request_target}
  ALL_EVENTS = (DEFAULT_BRANCH_EVENTS | NON_DEFAULT_BRANCH_EVENTS).freeze

  # Caution: Raising this threshold may increase DeliverHookEventJob and status API execution times.
  WORKFLOW_FILE_LIMIT = 60

  def actions_check_suites
    suites = check_suites.order(id: :desc)
    # Only use the lab app id if the flag is enabled in the repo for a way faster query
    if self.feature_enabled?(:launch_lab, memoize: false)
      suites.for_app_ids(GitHub.launch_github_app&.id, GitHub.launch_lab_github_app&.id)
    else
      suites.where(github_app_id: GitHub.launch_github_app&.id)
    end
  end

  # Inside .github/workflows. Any *.yml or *.yaml file counts
  def workflow_file_present?(branch)
    Actions::Workflow::WORKFLOW_PATHS.any? do |path|
      return false unless directory = self.directory(branch, path)
      yml_files_at_path(directory).any?
    end
  end

  def workflow_content(repository, branch, path)
    head = repository.ref_to_sha(branch)
    return nil if head.nil?

    repository.tree_entry(head, path)
  rescue GitRPC::Error
    nil
  end

  def workflow_contents(sha:, paths:)
    hash = {}
    Actions::Workflow::WORKFLOW_PATHS.each do |dir|
      directory = self.directory(sha, dir)
      next unless directory

      begin
        paths.each do |path|
          # Git RPC will return the information in ASCII, so we need it in ASCII here to do the comparison
          ascii_path = path&.b
          directory.each do |entry|
            if entry[:content].path == ascii_path
              hash[path] = entry[:content]
            end
          end
        end
      rescue GitRPC::NoSuchPath, GitRPC::ObjectMissing, GitRPC::InvalidObject
        []
      end
    end
    hash
  end

  # Stores existing workflows metadata in the database
  def persist_existing_workflows(disable_scheduled_workflows_on_fork: false)
    branch = self.default_branch
    Actions::Workflow::WORKFLOW_PATHS.flat_map do |path|
      return [] unless directory = self.directory(branch, path)

      yml_files_at_path(directory).map do |file|
        workflow_file_path = file["path"]
        parsed_workflow = Actions::ParsedWorkflow.parse_from_yaml(self, workflow_file_path)
        name = parsed_workflow.name

        state = if disable_scheduled_workflows_on_fork && self.public && self.fork? && parsed_workflow.has_schedule_trigger?
          # disable scheduled workflow by default in forked repositories
          "disabled_fork"
        elsif (workflow = Actions::Workflow.find_by(path: workflow_file_path, repository_id: self.id, imposer_repository_id: 0)) && workflow.disabled_manually?
          # keep manually disabled workflows disabled
          "disabled_manually"
        else
          "active"
        end
        ActiveRecord::Base.connected_to(role: :writing) do
          Actions::Workflow.create_or_update_workflow(workflow_file_path, name, self, state, nil, present_in_default_branch: true)
        end
      end
    end
  end

  def refresh_workflows
    old_workflows = workflows.not_deleted.where(present_in_default_branch: true)
    new_workflows = persist_existing_workflows
    return if old_workflows.empty?
    workflows_to_delete = old_workflows - new_workflows
    workflows_to_delete.each do |workflow|
      workflow.update(state: "deleted", present_in_default_branch: false)
    end
  end

  def workflow_runs_channel
    GitHub::WebSocket::Channels::workflow_runs(self)
  end

  # Checks for workflows in the default branch triggered by the event.
  #
  # Returns true if a matching workflow is found or the event can be associated with specific shas or refs other than the default branch.
  def has_workflow_trigger_for?(event_name, lab: false)
    return true unless DEFAULT_BRANCH_EVENTS.include?(event_name)

    head = default_branch_ref&.target_oid
    return false unless head

    path = lab ? Actions::Workflow::WORKFLOWS_LAB_PATH : Actions::Workflow::WORKFLOWS_PATH

    workflows_tree = tree(head, path)
    return false unless workflows_tree

    triggers = GitHub.cache.fetch(workflow_triggers_tree_cache_key(workflows_tree.oid), stats_key: "workflows.tree.triggers") do
      workflow_triggers(head, path, lab: lab, tree_oid: workflows_tree.oid)
    end

    triggers.include?(event_name)
  rescue StandardError => e # rubocop:todo Lint/GenericRescue
    Failbot.report(e, repo_id: self.id, event_name: event_name)
    true
  end

  private

  def yml_files_at_path(directory)
    entries = directory.tree_entries || []

    entries.select do |entry|
      entry.blob? && entry.display_name.ends_with?(".yml", ".yaml")
    end
  rescue GitRPC::NoSuchPath, GitRPC::ObjectMissing, GitRPC::InvalidObject
    []
  end

  # Parses workflows and returns the set of default branch events that trigger one or more workflows.
  def workflow_triggers(sha, workflows_path, lab: false, tree_oid: nil)
    start_time = GitHub::Dogstats.monotonic_time
    return Set[] unless directory = self.directory(sha, workflows_path)

    workflow_files = yml_files_at_path(directory)
    if workflow_files.size > WORKFLOW_FILE_LIMIT
      log_workflow_triggers(
        "Workflow files over the limit, allowing all workflow triggers",
        "gh.commit.sha" => sha,
        "gh.actions.tree_oid" => tree_oid,
        "gh.actions.workflow_files.count" => workflow_files.size,
        "gh.actions.workflow_environment" => lab ? "lab" : "production",
      )

      return DEFAULT_BRANCH_EVENTS
    end

    triggers = workflow_files.map do |file|
      workflow = Actions::ParsedWorkflow.parse_from_yaml(self, file["path"], sha)

      if workflow.nil? || workflow.trigger_events.empty?
        log_workflow_triggers(
          "No trigger events parsed, allowing all workflow triggers",
          "gh.commit.sha" => sha,
          "gh.actions.tree_oid" => tree_oid,
          "gh.actions.workflow.path" => file["path"],
          "gh.actions.workflow.file_size" => workflow&.file_size,
          "gh.actions.workflow_environment" => lab ? "lab" : "production",
        )

        return DEFAULT_BRANCH_EVENTS
      end

      workflow.trigger_events
    end.reduce(Set.new, :merge) & DEFAULT_BRANCH_EVENTS

    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("actions.parse_workflow_triggers.dist", elapsed)

    log_workflow_triggers(
      "Parsed triggers in default branch",
      "gh.commit.sha" => sha,
      "gh.actions.tree_oid" => tree_oid,
      "gh.actions.default_branch_triggers" => triggers.to_a.join(","),
      "gh.actions.workflow_files.count" => workflow_files.size,
      "gh.actions.workflow_environment" => lab ? "lab" : "production",
    )

    triggers
  end

  def workflow_triggers_tree_cache_key(tree_oid)
    ["repo", id, "tree", tree_oid, "workflows_tree_triggers", "v1"].join(":")
  end

  def log_workflow_triggers(message, **fields)
    GitHub.logger.info(message, fields.merge(
      "code.namespace" => self.class.name,
      "code.function" => "workflow_triggers",
      "gh.request_id" => GitHub.context[:request_id],
      "gh.catalog_service" => "github/actions",
      "gh.repo.id" => self.id,
      "gh.repo.global_id" => self.global_relay_id,
      "gh.actions.default_branch" => self.default_branch,
    ))
  end
end
