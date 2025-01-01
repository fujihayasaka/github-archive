# typed: true
# frozen_string_literal: true

class Api::CheckRuns < Api::App
  include ReceiveSchemaWithOpenApi

  class SilentTruncationError < RuntimeError
    def needs_redacting?
      true
    end
  end

  # List check runs for a specific commit
  get "/repositories/:repository_id/commits/*/check-runs", operation_id: "checks/list-for-ref" do
    repo = find_repo!

    control_access :read_check_run,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ref = params[:splat].first
    commit = find_commit!(repo, ref, @documentation_url)
    sha = commit.sha
    return deliver_error 404 if sha.blank?

    check_runs = CheckRun.order("id DESC")

    allowed_filter_params = %w[latest all]
    filter = params[:filter]
    filter = "latest" unless allowed_filter_params.include?(filter)

    most_recent_check_suites = CheckSuite.most_recent_check_suites_for_sha(repo.id, sha, CheckRun.default_max_check_suites_per_sha_limit)

    if most_recent_check_suites.length == CheckRun.default_max_check_suites_per_sha_limit
      GitHub.dogstats.increment("checks.check_runs_for_sha_limit_exceeded")

      GitHub.logger.info(
        "Fetching check runs for sha exceeded limit of #{CheckRun.default_max_check_suites_per_sha_limit} check suites",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.repository.id" => repo.id,
        "gh.repository.head_sha" => sha,
      )

      # there are a lot of check suites associated with the head_sha. API results will be inaccurate since not every check run will be evaluated
      check_suite_ids = most_recent_check_suites.pluck(:id)

      if app_id = params[:app_id].presence
        check_suite_ids = most_recent_check_suites.select { |cs| cs.github_app_id == app_id.to_i }.pluck(:id)
      end

      check_runs = check_runs.for_repository_id_and_check_suite_ids(repo.id, check_suite_ids)
      if name = params[:check_name].presence
        check_runs = check_runs.where(name: name).or(check_runs.with_display_name(name))
      end
      if status = params[:status].presence
        check_runs = check_runs.where(status: CheckRun.statuses[status])
      end

      check_runs = paginate_rel(check_runs)
      prefill_check_runs(check_runs, repo)

      deliver :check_runs_hash, { check_runs: check_runs, total_count: check_runs.total_entries }, repo: repo
    else
      GitHub.dogstats.increment("checks.check_runs_for_sha_below_limit")
      # If there are less check suites on the SHA than the limit than we can differ to the old logic that joins on the check suites table and is guaranated to be accurate
      if filter == "latest"
        check_runs = T.unsafe(check_runs).latest_for_sha_and_repository(sha, repo)
      else
        check_runs = check_runs.for_sha_and_repository_id(sha, repo.id)
      end
      if id = params[:app_id].presence
        check_runs = check_runs.for_app_id(id, repo.id)
      end
      if name = params[:check_name].presence
        check_runs = check_runs.where(name: name).or(check_runs.with_display_name(name))
      end
      if status = params[:status].presence
        check_runs = check_runs.where(status: CheckRun.statuses[status])
      end
      # latest_for_sha_and_repository, for_sha_and_repository_id, and for_app_id annotate the query
      # when used in conjunction, we need to uniq! the cross-shard-query-exempted annotation to keep only one
      check_runs.uniq!(:annotate)
      check_runs = paginate_rel(check_runs)

      prefill_check_runs(check_runs, repo)
      deliver :check_runs_hash, { check_runs: check_runs, total_count: check_runs.total_entries }, repo: repo
    end
  end

  # List check runs in a check suite
  get "/repositories/:repository_id/check-suites/:check_suite_id/check-runs", operation_id: "checks/list-for-suite" do
    repo = find_repo!

    control_access :read_check_run,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    check_suite = CheckSuite.find_by(id: params[:check_suite_id], repository_id: repo.id)
    record_or_404(check_suite)

    check_suite = T.must(check_suite)

    deliver_error! 404 if repo.id != check_suite.repository_id

    allowed_filter_params = %w[latest all]
    filter = params[:filter]
    filter = "latest" unless allowed_filter_params.include?(filter)

    if filter == "latest"
      check_runs = check_suite.latest_check_runs do |check_runs_relation|
        prepare_check_runs_relation(check_runs_relation)
      end
    end

    if filter == "all"
      check_runs = check_suite.check_runs.where(repository_id: repo.id).order("id DESC")
      check_runs = prepare_check_runs_relation(check_runs)
    end

    prefill_check_runs(check_runs, repo)
    deliver :check_runs_hash, { check_runs: check_runs, total_count: check_runs.total_entries }, repo: repo
  end

  # Get a check run.
  get "/repositories/:repository_id/check-runs/:check_run_id", operation_id: "checks/get" do
    repo = find_repo!
    check_run = CheckRun.includes(:check_suite).where(id: params[:check_run_id], repository_id: repo.id).first
    check_run = record_or_404(check_run)

    if check_run.check_suite.nil? || repo.id != check_run.repository_id
      deliver_error! 404
    end

    control_access :read_check_run,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver :check_run_hash, check_run, repo: repo
  end

  # Create a check run for a specific commit.
  post "/repositories/:repository_id/check-runs", operation_id: "checks/create" do
    repo = find_repo!
    # Return forbidden message about authentication, when the user could otherwise admin the repo
    if can_access_repo?(repo)
      set_forbidden_message "You must authenticate via a GitHub App.".freeze
    end

    control_access :write_check_run, resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_schema("check-run", "create-legacy")

    data["head_sha"] = find_commit!(repo, data["head_sha"], @documentation_url).oid
    data["status"] = "completed" if data["conclusion"]

    check_run_attrs = [
      :status, :conclusion, :details_url,
      :started_at, :completed_at, :external_id, :name
    ]
    output_attrs = [:title, :summary, :text]

    check_run_data = attr(data, *check_run_attrs)
    check_run_data = check_run_data.merge(attr(data["output"] || {}, *output_attrs))
    check_run_data[:repository] = repo
    truncator = CheckRun::Truncator.new(check_run_data["text"])
    check_run_data["text"] = truncator.truncate

    check_run = CheckRun.new check_run_data

    image_attrs = [:alt, :image_url, :caption]
    images_data_source = (data["output"] || {})["images"] || []
    images_data_source.each do |image|
      image_data = attr(image, *image_attrs)
      check_run.images << image_data
    end

    annotation_attrs = [
      :path, :annotation_level, :message,
      :start_line, :end_line, :start_column, :end_column,
      :raw_details, :title
    ]
    annotations_data_source = (data["output"] || {})["annotations"] || []
    annotations_data_source.each do |annotation|
      annotation_data = attr(annotation, *annotation_attrs)
      annotation_data = annotation_data.merge({ repository: check_run.repository })
      check_run.annotations.build annotation_data
    end

    check_run.actions = prepare_actions(data["actions"])

    check_suite = find_or_create_check_suite(head_sha: data["head_sha"], repo: repo)
    check_run.check_suite_id = check_suite.id

    if check_run.save
      if truncator.truncated?
        truncator.report_silent_truncation!(
          check_run: check_run,
          repo: repo,
          integration: current_integration,
          type: "a new",
        )
      end
      MergeQueues.execute_from_sha!(repo, check_run.head_sha)
      deliver :check_run_hash, check_run, repo: repo, status: 201
    else
      if truncator.truncated?
        truncator.report_silent_truncation!(
          check_run: check_run,
          repo: repo,
          integration: current_integration,
          type: "a new",
        )
      end
      deliver_error 422,
        errors: check_run.errors,
        documentation_url: @documentation_url
    end
  end

  # Update a check run
  patch "/repositories/:repository_id/check-runs/:check_run_id", operation_id: "checks/update" do
    repo = find_repo!
    # Return forbidden message about authentication, when the user could otherwise admin the repo
    if can_access_repo?(repo)
      set_forbidden_message "You must authenticate via a GitHub App.".freeze
    end

    control_access :write_check_run,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    check_run = CheckRun.includes(:check_suite).where(id: params[:check_run_id], repository_id: repo.id).first
    check_run = record_or_404(check_run)
    check_suite = T.must(check_run.check_suite)

    if repo.id != check_suite.repository_id
      deliver_error! 404
    end

    if current_integration&.id != check_suite.github_app_id
      deliver_error!(403, message: "Invalid app_id `#{check_suite.github_app_id}` - check run can only be modified by the GitHub App that created it.")
    end

    if check_run.is_actions_check_run?
      # Extra logging for gathering data before the FF is enabled
      GitHub.dogstats.increment("checks.actions_check_run_manually_updated")

      GitHub.logger.info(
        "Actions check run was manually updated using GITHUB_TOKEN using the update check run API",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.repository.id" => repo.id,
        "gh.check_run.id" => check_run.id,
      )

      if repo.feature_enabled?(:checks_restrict_update_check_run_with_github_token)
        deliver_error!(403, message: "This check run can only be updated internally by GitHub Actions")
      end
    end

    data = receive_with_schema("check-run", "update-legacy")

    check_run.name         = data["name"] if data["name"]
    check_run.details_url  = data["details_url"] if data["details_url"]
    check_run.conclusion   = data["conclusion"] if data["conclusion"]
    check_run.started_at   = data["started_at"] if data["started_at"]
    check_run.completed_at = data["completed_at"] if data["completed_at"]
    check_run.external_id  = data["external_id"] if data["external_id"]

    if data["conclusion"]
      check_run.status = "completed"
    elsif data["status"]
      check_run.status = data["status"]
    end

    output_attrs = [:title, :summary, :images, :text, :annotations]
    output_data  = attr(attr(data, :output)["output"], *output_attrs) || {}

    check_run.title   = output_data["title"] if output_data["title"]
    check_run.summary = output_data["summary"] if output_data["summary"]

    truncator = CheckRun::Truncator.new(output_data["text"])
    check_run.text = truncator.truncate
    if truncator.truncated?
      truncator.report_silent_truncation!(
        check_run: check_run,
        repo: repo,
        integration: current_integration,
        type: "an existing",
      )
    end

    image_attrs = [:alt, :image_url, :caption]
    images_data_source = output_data["images"] || []
    images_data_source.each do |image|
      image_data = attr(image, *image_attrs)
      check_run.images << image_data
    end

    annotation_attrs = [
      :path, :annotation_level, :message,
      :start_line, :end_line, :start_column, :end_column,
      :raw_details, :title
    ]

    annotations_data_source = output_data["annotations"] || []

    if GitHub.flipper[:checks_annotations_split_transaction].enabled?(repo)
      CheckAnnotation.transaction do
        annotations_data_source.each do |annotation|
          annotation_data = attr(annotation, *annotation_attrs)
          annotation_data = annotation_data.merge({ repository_id: check_run.repository_id, check_run_id: check_run.id })
          ca = CheckAnnotation.new annotation_data
          ca.save
        end
      end
    else
      annotations_data_source.each do |annotation|
        annotation_data = attr(annotation, *annotation_attrs)
        annotation_data = annotation_data.merge({ repository: check_run.repository })
        check_run.annotations.build annotation_data
      end
    end

    check_run.actions = prepare_actions(data["actions"])

    if check_run.save
      MergeQueues.execute_from_sha!(repo, check_run.head_sha)
      deliver :check_run_hash, check_run, repo: repo
    else
      deliver_error 422,
        errors: check_run.errors,
        documentation_url: @documentation_url
    end
  end

  get "/repositories/:repository_id/check-runs/:check_run_id/annotations", operation_id: "checks/list-annotations" do
    repo = find_repo!
    check_run = CheckRun.find_by(id: params[:check_run_id], repository_id: repo.id)
    record_or_404(check_run)

    check_run = T.must(check_run)

    if repo.id != check_run.repository_id
      deliver_error! 404
    end

    control_access :read_check_run,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    annotations = paginate_rel(check_run.annotations)
    deliver :check_annotation_hash, annotations
  end

  # Rerequest a check run
  post "/repositories/:repository_id/check-runs/:check_run_id/rerequest", operation_id: "checks/rerequest-run" do
    receive_with_openapi

    repo = find_repo!

    control_access :request_check_run,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    check_run = CheckRun.find_by(id: params[:check_run_id], repository_id: repo.id)
    record_or_404(check_run)
    check_run = T.must(check_run)
    check_suite = T.must(check_run.check_suite)

    deliver_error! 404 if repo.id != check_suite.repository_id

    unless allowed_to_modify_app?(app_id: check_suite.github_app_id)
      deliver_error!(403, message: "Invalid check_run_id `#{params[:check_run_id]}`")
    end

    unless check_suite.check_runs_rerunnable
      deliver_error!(422, message: "This check run is not rerequestable")
    end

    check_run.rerequest(actor: current_user)
    deliver_empty status: 201
  end

  private

  # Can they see that the repo exists?
  def can_access_repo?(repo)
    return true if repo.public?
    repo.pullable_by?(current_user) && scope?(current_user, "repo")
  end

  def find_or_create_check_suite(head_sha:, repo:)
    check_suite = Checks::Service.find_or_create_check_suite(
      github_app_id: current_integration.id,
      head_sha: head_sha,
      repo: repo,
    )
    return check_suite if check_suite.valid?

    deliver_error! 422,
      errors: check_suite.errors,
      documentation_url: @documentation_url
  end

  def prepare_check_runs_relation(check_runs)
    if name = params[:check_name].presence
      check_runs = check_runs.where(name: name).or(check_runs.with_display_name(name))
    end
    if status = params[:status].presence
      check_runs = check_runs.where(status: CheckRun.statuses[status])
    end

    paginate_rel(check_runs)
  end

  def prepare_actions(data)
    data ||= []
    data.map do |action|
      CheckRunAction.new(action["label"], action["identifier"], action["description"])
    end
  end

  def prefill_check_runs(check_runs, repo)
    GitHub::PrefillAssociations.prefill_associations(check_runs, [:creator, :check_suite])
    GitHub::PrefillAssociations.prefill_associations(check_runs, [:deployment]) if repo.can_use_environments_api?
  end
end
