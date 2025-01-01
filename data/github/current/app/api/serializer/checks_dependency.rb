# typed: true
# frozen_string_literal: true

module Api::Serializer::ChecksDependency
  extend T::Helpers

  requires_ancestor { T.class_of(Api::Serializer) }

  # Creates a Hash to be serialized to JSON.
  #
  # check_suite - CheckSuite instance.
  # options     -  Hash
  #
  # Returns a Hash if the CheckSuite exists, or nil.
  def check_suite_hash(check_suite, options = {})
    options = Api::SerializerOptions.from(options)
    hash = simple_check_suite_hash(check_suite, options)
    return hash if hash.nil?

    hash[:rerequestable] = check_suite.rerequestable
    hash[:runs_rerequestable] = check_suite.check_runs_rerunnable
    hash[:latest_check_runs_count] = Checks.domain.check_runs.latest_ids_for_check_suite(check_suite).size
    hash[:check_runs_url]   = url("/repos/#{check_suite.repository.name_with_owner_for_api(use: options[:serialize_login])}/check-suites/#{check_suite.id}/check-runs", options)
    hash[:head_commit]      = simple_commit_hash(Repositories.domain.commits.by_oid(repository: check_suite.repository, commit_oid: check_suite.head_sha))
    hash[:repository]       = simple_repository_hash(check_suite.repository, options)
    hash
  end

  # Creates a hash from a CheckSuite to be serialized to JSON. A short representation
  # suitable for sub-resources.
  #
  # check_suite - CheckSuite instance
  #
  # Returns a Hash if the CheckSuite exists, or nil
  def simple_check_suite_hash(check_suite, options = {})
    return nil unless check_suite

    hash = {
      id:            check_suite.id,
      node_id:       global_id_for(check_suite, options),
      head_branch:   check_suite.head_branch,
      head_sha:      check_suite.head_sha,
      status:        check_suite.status,
      conclusion:    check_suite.conclusion,
      url:           url("/repos/#{check_suite.repository.name_with_owner_for_api(use: options[:serialize_login])}/check-suites/#{check_suite.id}", options),
      before:        check_suite.push&.before,
      after:         check_suite.push&.after,
      pull_requests: related_pull_requests(check_suite, options),
      app:           integration_hash(check_suite.github_app, options),
      created_at:    time(check_suite.created_at),
      updated_at:    time(check_suite.updated_at),
    }

    hash
  end

  def check_suites_hash(data, options = {})
    check_suites = data.fetch(:check_suites, [])
    check_suite_hashes = check_suites.map do |suite|
      check_suite_hash(suite, options)
    end

    {}.tap do |h|
      h[:total_count]  = data[:total_count]
      h[:check_suites] = check_suite_hashes
    end
  end

  # Creates a Hash to be serialized to JSON.
  #
  # check_run - CheckRun instance.
  #
  # Returns a Hash if the CheckRun exists, or nil.
  def check_run_hash(run, options = {})
    hash = simple_check_run_hash(run, options)
    return hash if hash.nil?

    hash[:output]        = check_output_fields(run, options)
    hash[:check_suite]   = { id: run.check_suite_id }
    hash[:app]           = integration_hash(run.github_app, options)
    hash[:pull_requests] = related_pull_requests(run.check_suite, options)

    if options[:repo].can_use_environments_api?
      hash[:deployment] = simple_deployment_hash(run.deployment, options) if run.deployment.present?
    end
    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # check_run - CheckRun instance.
  #
  # Returns a Hash if the CheckRun exists, or nil.
  def simple_check_run_hash(run, options = {})
    return nil unless run

    {}.tap do |h|
      h[:id]           = run.id
      h[:name]         = run.visible_name
      h[:node_id]      = global_id_for(run, options)
      h[:head_sha]     = run.head_sha
      h[:external_id]  = run.external_id.to_s
      h[:url]          = url("/repos/#{run.repository.name_with_owner_for_api(use: options[:serialize_login])}/check-runs/#{run.id}", options)
      h[:html_url]     = html_url("#{run.permalink}")
      h[:details_url]  = run.details_url
      h[:status]       = run.status
      h[:conclusion]   = run.conclusion
      h[:started_at]   = time(run.started_at)
      h[:completed_at] = time(run.completed_at)
    end
  end

  # Creates a Hash to be serialized to JSON.
  #
  # check_runs - CheckRun active record relation or Array of CheckRun instances.
  #
  # Returns a Hash.
  def check_runs_hash(data, options = {})
    check_runs = data.fetch(:check_runs, [])
    check_run_hashes = check_runs.map do |run|
      check_run_hash(run, options)
    end

    {}.tap do |h|
      h[:total_count] = data[:total_count]
      h[:check_runs]  = check_run_hashes
    end
  end

  # Creates a Hash to be serialized to JSON.
  #
  # repo - A Repository instance.
  #
  # Returns a Hash.
  def check_suite_preferences_hash(repo, options = {})
    data = repo.check_suite_preferences

    hash = {}
    hash[:preferences]         = {}
    hash[:repository]          = simple_repository_hash(repo, options)

    hash[:preferences][:auto_trigger_checks] = []
    data[:auto_trigger_checks].each do |h|
      hash[:preferences][:auto_trigger_checks] << {
        app_id: h[:app][:id], setting: h[:setting]
      }
    end

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # check_run - CheckRun instance.
  #
  # Returns a Hash.
  def check_output_fields(check_run, options = {})
    {}.tap do |h|
      h[:title]             = check_run.title
      h[:summary]           = check_run.summary
      h[:text]              = check_run.text
      h[:annotations_count] = check_run.annotations.count
      h[:annotations_url]   = url("/repos/#{check_run.repository.name_with_owner_for_api(use: options[:serialize_login])}/check-runs/#{check_run.id}/annotations", options)
    end
  end

  # Creates a Hash to be serialized to JSON.
  #
  # annotation - CheckAnnotation instance.
  #
  # Returns a Hash.
  def check_annotation_hash(annotation, _ = {})
    {}.tap do |h|
      h[:path] = annotation.path
      h[:blob_href] = annotation.blob_href
      h[:start_line] = annotation.start_line
      h[:start_column] = annotation.start_column
      h[:end_line] = annotation.end_line
      h[:end_column] = annotation.end_column
      h[:annotation_level] = annotation.annotation_level
      h[:title] = annotation.title
      h[:message] = annotation.message
      h[:raw_details] = annotation.raw_details
    end
  end

  def related_pull_requests(check_suite, options)
    check_suite.matching_pull_requests(options[:current_user])&.map do |pull_request|
      minimal_pull_request_hash(pull_request, options)
    end
  end
end
