# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class CreateDependabotAnnotationsJob < ApplicationJob

  resolve_tenant_context do |args|
    repository = Checks.domain.check_runs.unsafe_for_id(args[:check_run_id])&.repository
    Business.find(repository.tenant_id) if repository.present?
  end

  queue_as :dependabot

  attr_reader :annotation_creator

  use_primaries ApplicationRecord::RepositoriesActionsChecks, ApplicationRecord::IssuesPullRequests

  use_replicas ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Permissions,
    ApplicationRecord::Spokes

  before_perform do |job|
    context = { job: job.class.name }
    args = job.arguments.first
    context = context.merge(args) if args && args.is_a?(Hash)
    Failbot.push(context)

    @annotation_creator = Dependabot::AnnotationCreator.new
  end

  retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer do |job, error|
    # This logging/erroring is because we previously had a retry loop before calling this job due to a race condition
    # As the active job will retry on its own this logging can most likely be removed once we establish that these jobs complete
    GitHub.logger.error(
      "Record not found",
      "code.namespace" => "CreateDependabotAnnotationsJob",
      "code.function" => "perform",
      "gh.check_run.id" => job.check_run_id,
      "gh.pull_request.number" => job.pull_request_number,
    )
    Failbot.report(error)
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  CheckRunOrSuiteNotFoundError = Class.new(StandardError)
  CheckRunNotFoundError = Class.new(CheckRunOrSuiteNotFoundError)
  CheckSuiteNotFoundError = Class.new(CheckRunOrSuiteNotFoundError)

  retry_on CheckRunOrSuiteNotFoundError, wait: 1.minute, attempts: 2 do |job, error|
    GitHub.logger.error(
      "Failed due to Check run or suite not found error. Trying one more time.",
      "code.namespace" => "CreateDependabotAnnotationsJob",
      "code.function" => "CheckRunOrSuiteNotFoundError.catch",
      "gh.check_run.id" => job.check_run_id,
      :exception => error,
    )
    GitHub.dogstats.increment("dependabot.annotations_job.find_check")
  end

  def perform(*args)
    log "Starting job."

    return fail_check_run_because_dependabot_disabled unless GitHub.dependabot_enabled? && repository&.active?
    return ensure_check_suite_concluded if pr_already_closed_with_check_run_conclusion
    return no_autofix_job_id if autofix_job_id.blank?
    return no_annotation_location if annotation_location.blank?

    lock! do

      annotation_attributes = build_annotation_attributes(autofix_job_id, annotation_location)

      if annotation_attributes.blank?
        return mark_check_run_neutral
      end

      new_annotations_count = annotation_creator.create_annotations(check_run, annotation_attributes)
      log "Created #{new_annotations_count} new annotations."
      manage_comments_if_possible(new_annotations_count)
    end
  end

  def check_run_id
    arguments.first[:check_run_id]
  end

  def pull_request_number
    arguments.first[:pull_request_number]
  end

  def autofix_job_id
    arguments.first[:autofix_job_id]
  end

  def level
    arguments.first[:level]
  end

  def message
    arguments.first[:message]
  end

  def annotation_location
    arguments.first[:annotation_location]
  end

  def mark_check_run_neutral
    check_run.update(conclusion: "neutral")
  end

  def ensure_check_suite_concluded
    # Make sure that the check_suite has the proper conclusion,
    # in case it missed it due to a race condition
    if check_run.check_suite.conclusion.nil?
      check_run.check_suite.set_rollup_values!
      # Emit a metric if this actually changed something
      GitHub.dogstats.increment("dependabot.stale_check_suite") unless check_run.check_suite.conclusion.nil?
    end
  end

  def pr_already_closed_with_check_run_conclusion
    check_run.conclusion.present? && pull_request.present? && !pull_request.open?
  end

  def fail_check_run_because_dependabot_disabled
    check_run.update(conclusion: "failure", title: "Dependabot updates is not enabled on this repository")
  end

  def no_autofix_job_id
    log_error("No valid autofix_job_id found. Skipping annotation creation.")
    check_run.update(conclusion: "neutral", title: "No valid autofix job found")
  end

  def no_annotation_location
    log_error("No valid annotation location found. Skipping annotation creation.")
    check_run.update(conclusion: "neutral", title: "No valid annotation location found")
  end

  private

  def manage_comments_if_possible(new_annotations_count)
    return log("Cannot create review comments. The pull request is not present") unless pull_request.present?

    comment_creator = Dependabot::CommentCreator.new(pull_request: pull_request, check_run: check_run, reviewer: dependabot_bot)

    if new_annotations_count <= 0
      log("No need to create new review comments since we didn't create any new annotations")
      return
    end

    location = Dependabot::CommentCreator::Location.new(
      file_path: annotation_location[:file_path],
      start_line: annotation_location[:start_line],
      end_line: annotation_location[:end_line]
    )

    comment_creator.create_review_comments(location: location)
  end

  def pull_request
    return unless pull_request_number.present?

    @pull_request ||= PullRequest.with_number_and_repo(pull_request_number, repository)
  end

  # The reason why we are creating annotations
  def reason
    arguments.first[:reason] || :unknown
  end

  # Helper method for all logging from `perform` and the methods it calls
  def log(msg, other_log_params = {})
    GitHub.logger.info(msg,
      "code.namespace" => "CreateDependabotAnnotationsJob",
      "code.function" => "perform",
      "gh.repo.id" => repository&.id,
      "gh.check_run.id" => check_run&.id,
      "gh.pull_request.number" => pull_request_number,
      **other_log_params
    )
  end

  def log_error(msg, other_log_params = {})
    GitHub.logger.error(msg,
      "code.namespace" => "CreateDependabotAnnotationsJob",
      "code.function" => "perform",
      "gh.repo.id" => repository&.id,
      "gh.check_run.id" => check_run&.id,
      "gh.pull_request.number" => pull_request_number,
      **other_log_params
    )
  end

  def dependabot_bot
    return @dependabot_bot if defined?(@dependabot_bot)

    dependabot_app = Apps::Privileged.integration(:dependabot) or fail "dependabot integration not installed!"
    @dependabot_bot = dependabot_app.bot
  end

  def lock!
    restraint = GitHub::Restraint.new
    lock_key = "#{self.class.name}:#{check_run.id}"
    max_concurrent_jobs = 1
    lock_ttl = 5.minutes
    restraint.lock!(lock_key, max_concurrent_jobs, lock_ttl) do
      log "Obtained lock."
      yield
    end
  end

  def check_run
    @check_run ||= Checks.domain.check_runs.unsafe_for_id(check_run_id).tap do |cr|
      raise(CheckRunNotFoundError) if cr.nil?
      raise(CheckSuiteNotFoundError) if cr.check_suite.nil?
    end
  end

  def repository
    @repository ||= check_run.repository
  end

  def build_annotation_attributes(autofix_job_id, annotation_location)
    # Validate presence of required attributes and log an error if any are missing or blank
    required_keys = %i[file_path start_line end_line start_column end_column]
    missing_keys = required_keys.reject { |key| annotation_location[key].present? }

    if missing_keys.any?
      log_error("Missing or blank keys in annotation_location: #{missing_keys.join(', ')}. Skipping annotation creation.")
      return {}
    end

    {
      autofix_job_id: autofix_job_id,
      level: level,
      message: message,
      locations: [{
        artifactLocation: annotation_location[:file_path],
        startLine: annotation_location[:start_line],
        endLine: annotation_location[:end_line],
        startColumn: annotation_location[:start_column],
        endColumn: annotation_location[:end_column]
      }]
    }
  rescue KeyError => e
    log_error("Missing key in annotation_location: #{e.message}. Skipping annotation creation.")
    {}
  rescue TypeError => e
    log_error("Invalid type in annotation_location: #{e.message}. Skipping annotation creation.")
    {}
  end
end
