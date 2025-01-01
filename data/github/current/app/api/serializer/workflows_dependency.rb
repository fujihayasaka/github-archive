# typed: false
# frozen_string_literal: true

module Api::Serializer::WorkflowsDependency
  # Creates a hash to be serialized to JSON.
  #
  # workflow_run - WorkflowRun instance.
  # options      - Hash
  #
  # Returns a Hash if the WorkflowRun exists, or nil.
  def workflow_run_hash(workflow_run, options = {})
    options = Api::SerializerOptions.from(options)
    hash = simple_workflow_run_hash(workflow_run, options)
    return hash if hash.nil?

    workflow_run_prefix = workflow_run_path(workflow_run)

    hash[:jobs_url]             = url("#{workflow_run_prefix}/jobs")
    hash[:logs_url]             = url("#{workflow_run_prefix}/logs")
    hash[:check_suite_url]      = url("/repos/#{workflow_run.repository.name_with_owner_for_api(use: options[:serialize_login])}/check-suites/#{workflow_run.check_suite_id}")
    hash[:artifacts_url]        = url("#{workflow_run_prefix}/artifacts")
    hash[:cancel_url]           = url("#{workflow_run_prefix}/cancel")
    hash[:rerun_url]            = url("#{workflow_run_prefix}/rerun")
    hash[:previous_attempt_url] = url_or_nil(previous_workflow_run_attempt_path(workflow_run, options))
    hash[:workflow_url]         = url(workflow_path(workflow_run.workflow, options))
    hash[:head_commit]          = simple_commit_hash(workflow_run.commit)
    hash[:repository]           = simple_repository_hash(workflow_run.repository, options)
    hash[:head_repository]      = simple_repository_hash(workflow_run.head_repository, options)
    hash
  end

  def workflow_runs_hash(data, options)
    workflow_runs = data[:workflow_runs] || []
    workflow_run_hashes = workflow_runs.map do |workflow_run|
      workflow_run_hash(workflow_run, options)
    end

    {
      total_count: data[:total_count],
      workflow_runs: workflow_run_hashes,
    }
  end

  # A workflow_run_execution_hash is the same as a workflow_run_hash but customized to the
  # fields that are unique to that execution.
  def workflow_run_execution_hash(execution, options = {})
    options = Api::SerializerOptions.from(options)
    hash = workflow_run_hash(execution.workflow_run, options)
    return hash if hash.nil?

    workflow_run_execution_prefix = "#{workflow_run_path(execution.workflow_run)}/attempts/#{execution.attempt}"

    hash[:run_attempt]          = execution.attempt
    hash[:status]               = execution.status
    hash[:conclusion]           = execution.conclusion
    hash[:referenced_workflows] = referenced_workflows_array(execution)
    hash[:created_at]           = time(execution.created_at)
    hash[:updated_at]           = time(execution.updated_at)
    hash[:run_started_at]       = time(execution.started_at)
    hash[:previous_attempt_url] = url_or_nil(previous_workflow_run_attempt_path(execution, options))
    hash[:logs_url]             = url("#{workflow_run_execution_prefix}/logs")
    hash[:jobs_url]             = url("#{workflow_run_execution_prefix}/jobs")
    hash[:triggering_actor]     = simple_user_hash(execution.actor, options)
    hash
  end

  def gate_approval_logs_hash(data, options)
    gate_approval_logs = data[:gate_approval_logs]
    gate_approval_logs.map do |gate_approval_log|
      gate_approval_log_hash(gate_approval_log, options)
    end
  end

  def gate_approval_log_hash(gate_approval_log, options)
    hash = {}
    hash[:user] = simple_user_hash(gate_approval_log.user, options)
    hash[:state] = gate_approval_log.state
    hash[:comment] = gate_approval_log.comment
    hash[:environments] = gate_approval_log.gate_approvals.map do |gate_approval|
      simple_environment_hash(gate_approval.environment, options)
    end
    hash
  end

  # Creates a hash from a WorkflowRun to be serialized to JSON. A short representation
  # suitable for sub-resources.
  #
  # workflow_run - WorkflowRun instance
  #
  # Returns a Hash if the WorkflowRun exists, or nil
  def simple_workflow_run_hash(workflow_run, options = {})
    return nil unless workflow_run

    hash = {
      id:                  workflow_run.id,
      name:                workflow_run.name,
      node_id:             global_id_for(workflow_run, options),
      head_branch:         workflow_run.head_branch,
      head_sha:            workflow_run.head_sha,
      path:                workflow_run.workflow_file_path,
      display_title:       workflow_run.title,
      run_number:          workflow_run.run_number,
      event:               workflow_run.event,
      status:              workflow_run.status,
      conclusion:          workflow_run.conclusion,
      workflow_id:         workflow_run.workflow_id,
      check_suite_id:      workflow_run.check_suite.id,
      check_suite_node_id: global_id_for(workflow_run.check_suite, options),
      url:                 url(workflow_run_path(workflow_run)),
      html_url:            workflow_run.permalink,
      pull_requests:       options[:exclude_pull_requests] ? [] : related_pull_requests(workflow_run.check_suite, options),
      created_at:          time(workflow_run.created_at),
      updated_at:          time(workflow_run.updated_at),
      actor:               simple_user_hash(workflow_run.actor, options),
    }

    hash[:external_id] = workflow_run.check_suite.external_id if include_external_id(options[:current_user])
    hash[:run_attempt] = workflow_run.latest_workflow_run_execution&.attempt || 1
    hash[:referenced_workflows] = referenced_workflows_array(workflow_run.latest_workflow_run_execution)
    hash[:run_started_at] = time(workflow_run.started_at)
    hash[:triggering_actor] = simple_user_hash(workflow_run.latest_workflow_run_execution.actor, options) if workflow_run.latest_workflow_run_execution

    hash
  end

  def referenced_workflows_array(execution)
    return [] if execution.nil?
    workflow_run_execution = Actions::WorkflowRunExecution.with_referenced_workflows.find_by(id: execution.id, repository: execution.repository)
    return [] if workflow_run_execution.referenced_workflows.blank?
    result = JSON.parse(workflow_run_execution.referenced_workflows)
    result.presence || []
  end

  # Creates a hash to be serialized to JSON.
  #
  # workflow_job_run - WorkflowJobRun instance.
  # options      - Hash
  #
  # Returns a Hash if the WorkflowRun exists, or nil.
  def simple_workflow_job_run_hash(workflow_job_run, options = {})
    return nil unless workflow_job_run&.check_run.present?
    check_run = workflow_job_run.check_run
    {
      id:                  workflow_job_run.id,
      name:                check_run.display_name,
      status:              check_run.status,
      conclusion:          check_run.conclusion,
      html_url:            html_url(check_run.permalink(check_suite_focus: true)),
      created_at:          time(check_run.created_at),
      updated_at:          time(check_run.updated_at),
      environment:         check_run.deployment&.environment
    }
  end

  # Creates a hash to be serialized to JSON.
  #
  # workflow_job_run - WorkflowJobRun instance.
  # options      - Hash
  #
  # Returns a Hash if the WorkflowRun exists, or nil.
  def simple_workflow_job_runs_hash(workflow_job_runs, options = {})
    approvals_hashes = workflow_job_runs.map do |workflow_job_run|
      check_run = workflow_job_run.check_run
      {
        id:                  workflow_job_run.id,
        name:                check_run.display_name,
        status:              check_run.status,
        conclusion:          check_run.conclusion,
        html_url:            html_url(check_run.permalink(check_suite_focus: true)),
        created_at:          time(check_run.created_at),
        updated_at:          time(check_run.updated_at),
        environment:         check_run.deployment&.environment
      }
    end
    approvals_hashes
  end

  # Creates a hash to be serialized to JSON.
  #
  # workflow - Workflow instance.
  # options  - Hash
  #
  # Returns a Hash if the Workflow exists, or nil.
  def workflow_hash(workflow, options = {})
    options = Api::SerializerOptions.from(options)
    simple_workflow_hash(workflow, options)
  end

  # Creates a hash from a Workflow to be serialized to JSON. A short representation
  # suitable for sub-resources.
  #
  # workflow - Workflow instance
  #
  # Returns a Hash if the Workflow exists, or nil
  def simple_workflow_hash(workflow, options = {})
    return nil unless workflow
    repo = workflow.repository

    workflow_name = workflow.name.present? ? workflow.url_safe_name : workflow.path
    # Workflows generated by very old check suites may not have name, nor path
    # We don't want to raise an exception when generating the URL and we want to keep
    # the badge_url a required field, so we just generate a dummy URL
    workflow_name = ".github" unless workflow_name.present?
    # dynamic workflows generated by e.g. pages or dependabot don't have a blob path
    # we can use workflow.filename to link to the right place
    if workflow.path.start_with?(Actions::Workflow::DYNAMIC_BASE_PATH)
      badge_url = url_helpers.workflow_badge_by_file_url(
        repository: repo,
        user_id: repo.owner,
        workflow_filename: workflow.filename,
        host: GitHub.host_name_with_tenant,
        protocol: GitHub.scheme
      )
      html_url = url_helpers.workflow_runs_list_url(
        repository: repo,
        user_id: repo.owner,
        workflow_file_name: workflow.filename,
        host: GitHub.host_name_with_tenant,
        protocol: GitHub.scheme
      )
    else
      badge_url = url_helpers.workflow_badge_url(
        repository: repo,
        user_id: repo.owner,
        workflow_name: workflow_name,
        host: GitHub.host_name_with_tenant,
        protocol: GitHub.scheme
      )
      html_url = url_helpers.blob_url(
        user_id: repo.owner,
        repository: repo,
        name: repo.default_branch,
        path: workflow.path,
        host: GitHub.host_name_with_tenant,
        protocol: GitHub.scheme
      )
    end

    url = url(workflow_path(workflow, options))

    {
      id: workflow.id,
      node_id: global_id_for(workflow, options),
      name: workflow.name,
      path: workflow.path,
      state: workflow.state,
      created_at: workflow.created_at,
      updated_at: workflow.updated_at,
      url: url,
      html_url: html_url,
      badge_url: badge_url,
    }
  end

  def workflows_hash(data, options)
    workflows = data[:workflows] || []
    workflows_hashes = workflows.map do |workflow|
      workflow_hash(workflow, options)
    end

    {
      total_count: data[:total_count],
      workflows: workflows_hashes,
    }
  end

  def run_dynamic_workflow_hash(data, options = {})
    repo = simple_repository_hash(data[:repository], options)

    {
      execution_id: data[:execution_id],
      workflow_run_id: data[:workflow_run_id],
      repository: repo,
      workflow: data[:workflow],
      ref: data[:ref],
      workflow_name: data[:workflow_name],
      slug: data[:slug]
    }
  end

  private

  # Determines if the external_id should be exposed in the payload, currently only true for Dependabot installations.
  #
  # This should be removed in favour of a more durable contract between Actions and Dependabot in future.
  # see: https://github.com/github/c2c-actions/pull/3247
  def include_external_id(current_user)
    return false unless current_user&.bot?

    current_user.integration.dependabot_github_app?
  end

  def workflow_path(workflow, options = {})
    return "/repos/#{workflow.repository.name_with_owner_for_api(use: options[:serialize_login])}/actions/required_workflows/#{workflow.id}" if workflow.required?
    "/repos/#{workflow.repository.name_with_owner_for_api(use: options[:serialize_login])}/actions/workflows/#{workflow.id}"
  end

  def workflow_run_path(workflow_run, options = {})
    "/repos/#{workflow_run.repository.name_with_owner_for_api(use: options[:serialize_login])}/actions/runs/#{workflow_run.id}"
  end

  def previous_workflow_run_attempt_path(entity, options = {})
    case entity
    when Actions::WorkflowRunExecution
      previous_execution = entity.previous_execution
      "#{workflow_run_path(entity.workflow_run, options)}/attempts/#{previous_execution.attempt}" if previous_execution
    when Actions::WorkflowRun
      "#{workflow_run_path(entity, options)}/attempts/#{entity.previous_attempt_num}" if entity.has_multiple_attempts
    end
  end

  def url_or_nil(path)
    return nil if path.blank?

    url(path)
  end

  def url_helpers
    UrlHelpers
  end
end
