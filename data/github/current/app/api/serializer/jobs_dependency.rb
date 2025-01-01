# typed: false
# frozen_string_literal: true

module Api::Serializer::JobsDependency
  # Creates a hash to be serialized to JSON.
  #
  # job      - Job (CheckRun) instance.
  # options  - Hash
  #
  # Returns a Hash if the job exists, or nil.
  def job_hash(data, options = {})
    job = data.fetch(:job, nil)
    if job.nil? # fallback to old logic
      GitHub.dogstats.increment("actions.job_hash_fallback")
      job = data
    end
    steps = data.fetch(:steps, [])
    options = Api::SerializerOptions.from(options)
    hash = simple_job_hash(job, options)
    return hash if hash.nil?

    hash[:name] = job.visible_name

    if steps.any?
      hash[:steps] = steps_to_hash(steps)
    else
      # if we are in progress, get data from actions service via launch grpcs
      GitHub.dogstats.time("actions.checks.steps.time", tags: ["source:#{job.passthrough_steps? ? "grpc" : "db"}", "request_type:rest"]) do
        steps = job.passthrough_steps? ? job.steps_from_backend : job.get_steps
        hash[:steps] = steps_to_hash(steps)
      end
    end

    hash[:check_run_url] = url("/repos/#{job.repository.name_with_owner_for_api(use: options[:serialize_login])}/check-runs/#{job.id}")

    workflow_job_run = job.workflow_job_run

    if workflow_job_run
      hash[:labels] = workflow_job_run.label_data || []
      hash[:runner_id] = workflow_job_run.runner_id
      hash[:runner_name] = workflow_job_run.runner_name
      hash[:runner_group_id] = workflow_job_run.runner_group_id
      hash[:runner_group_name] = workflow_job_run.runner_group_name
    end

    hash
  end

  # Creates a hash from a job (CheckRun) to be serialized to JSON. A short representation
  # suitable for sub-resources.
  #
  # job - CheckRun instance
  #
  # Returns a Hash if the CheckRun exists, or nil
  def simple_job_hash(job, options = {})
    return nil unless job

    workflow_run = job.check_suite.workflow_run
    return nil unless workflow_run

    {}.tap do |h|
      h[:id]           = job.id
      h[:run_id]       = workflow_run.id
      h[:workflow_name] = workflow_run.name
      h[:head_branch] = workflow_run.head_branch
      h[:run_url]      = url(workflow_run_path(workflow_run))
      h[:run_attempt]  = job.workflow_job_run&.workflow_run_execution&.attempt || 1
      h[:node_id]      = global_id_for(job, options)
      h[:head_sha]     = job.head_sha
      h[:url]          = url("/repos/#{job.repository.name_with_owner_for_api(use: options[:serialize_login])}/actions/jobs/#{job.id}")
      h[:html_url]     = html_url("#{job.permalink}")
      h[:status]       = job.status
      h[:conclusion]   = job.conclusion
      h[:created_at]   = time(job.created_at)
      h[:started_at]   = time(job.started_at)
      h[:completed_at] = time(job.completed_at)
    end
  end

  # Creates a Hash to be serialized to JSON.
  #
  # jobs - CheckRun active record relation or Array of CheckRun instances.
  #
  # Returns a Hash.
  def jobs_hash(data, options = {})
    jobs = data.fetch(:jobs, [])

    if jobs.is_a?(ActiveRecord::Relation)
      jobs = jobs.where(repository_id: data[:repository_id])
    end

    steps = {}
    workflow_run = data.fetch(:workflow_run, nil)
    if workflow_run && workflow_run.check_suite.completed_steps_via_results_service?
      steps = workflow_run.check_suite.steps_from_results(jobs)
    end

    job_hashes = jobs.map do |run|
      job_steps = steps[run.id] || []
      job_hash({ job: run, steps: job_steps }, options)
    end

    {}.tap do |h|
      h[:total_count] = data[:total_count]
      h[:jobs] = job_hashes
    end
  end

  private

  def steps_to_hash(steps)
    hash_steps = steps.map do |step|
      {
        name:         step.name,
        status:       step.status,
        conclusion:   step.conclusion,
        number:       step.number,
        started_at:   time(step.started_at),
        completed_at: time(step.completed_at),
      }
    end

    hash_steps.sort_by { |s| s[:number] }
  end
end
