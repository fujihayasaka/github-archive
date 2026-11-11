# typed: true
# frozen_string_literal: true

module CheckRun::LicenseComplianceDependency
  LICENSE_COMPLIANCE_CHECK_SUITE_NAME = "License compliance".freeze
  LICENSE_COMPLIANCE_CHECK_RUN_NAME = "License compliance check".freeze
  LICENSE_COMPLIANCE_DOCS_URL = "https://docs.github.com/en/enterprise-cloud@latest/early-access/code-security/supply-chain-security/enforcing-license-policy-across-an-enterprise".freeze

  extend T::Helpers

  requires_ancestor { CheckRun }

  module ClassMethods
    extend T::Helpers

    include Kernel

    sig { params(repo: Repository, head_sha: String, check_job_status: Integer, log_message: String, progressed_at: Time, title: T.nilable(String)).returns([CheckSuite, T::Boolean]) }
    def create_or_update_license_compliance_check_run!(repo:, head_sha:, check_job_status:, log_message:, progressed_at:, title: nil)
      check_suite = find_or_create_license_compliance_check_suite!(repo: repo, head_sha: head_sha)
      is_new = T.let(false, T::Boolean)

      check_suite.with_lock do
        is_new = check_suite.name.blank?

        if is_new
          check_suite.update!(
            name: LICENSE_COMPLIANCE_CHECK_SUITE_NAME,
            check_runs_rerunnable: false,
            rerequestable: false,
          )
        end

        check_run = check_suite.check_runs.where(name: LICENSE_COMPLIANCE_CHECK_RUN_NAME, repository_id: repo.id).order(id: :desc).first ||
          check_suite.check_runs.create!(name: LICENSE_COMPLIANCE_CHECK_RUN_NAME, repository: repo, details_url: LICENSE_COMPLIANCE_DOCS_URL)

        log_context = {
          "code.namespace" => "CheckRun::LicenseComplianceDependency",
          "code.function" => "create_or_update_license_compliance_check_run!",
          "check_suite_id" => check_suite.id,
          "check_run_id" => check_run.id,
          "repository_id" => repo.id,
          "head_sha" => head_sha,
          "check_job_status" => check_job_status,
          "progressed_at" => progressed_at.utc.iso8601(6),
          "text_lines_before" => check_run.text&.lines&.count.to_i,
          "status_before" => check_run.status,
          "conclusion_before" => check_run.conclusion,
        }
        GitHub.logger.info("License compliance check run: entering with_lock", log_context)

        unless check_run.skipped?
          check_run.update_with_progress!(check_job_status: check_job_status, log_message: log_message, progressed_at: progressed_at, title: title)

          GitHub.logger.info("License compliance check run: after update_with_progress", log_context.merge(
            "text_lines_after" => check_run.text&.lines&.count.to_i,
            "status_after" => check_run.status,
            "conclusion_after" => check_run.conclusion,
          ))
        end
      end

      [check_suite, is_new]
    end

    sig { params(repo: Repository, head_branch: String).void }
    def skip_old_license_compliance_check_runs!(repo:, head_branch:)
      current_tip = repo.heads.find(head_branch)&.target_oid
      return unless current_tip

      old_runs = CheckRun
        .joins(:check_suite)
        .where(check_suites: {
          github_app_id: Apps::Privileged.integration_id(:license_compliance),
          head_branch: head_branch,
          repository_id: repo.id,
        })
        .where.not(check_suites: { head_sha: current_tip })
        .where(name: LICENSE_COMPLIANCE_CHECK_RUN_NAME, repository_id: repo.id)
        .where.not(status: :completed)

      old_runs.each do |run|
        run.update!(status: :completed, conclusion: :skipped, completed_at: Time.now)
      end
    end

    private

    sig { params(repo: Repository, head_sha: String).returns(CheckSuite) }
    def find_or_create_license_compliance_check_suite!(repo:, head_sha:)
      Checks.domain.check_suites.find_or_create(
        repo: repo,
        head_sha: head_sha,
        github_app_id: Apps::Privileged.integration_id(:license_compliance),
      )
    end
  end

  mixes_in_class_methods(ClassMethods)

  sig { params(line: String).returns(T.nilable(Time)) }
  def self.extract_timestamp(line)
    match = line.match(/\A\[([^\]]+)\]/)
    return unless match

    ts = T.must(match[1])
    # Require explicit UTC offset (Z or +HH:MM) to avoid ambiguous local times
    return unless ts.match?(/Z|[+-]\d{2}:\d{2}\z/)

    Time.iso8601(ts)
  rescue ArgumentError
    nil
  end

  sig { params(check_job_status: Integer, log_message: String, progressed_at: Time, title: T.nilable(String)).void }
  def update_with_progress!(check_job_status:, log_message:, progressed_at:, title: nil)
    is_latest_event = insert_log_into_text(log_message, progressed_at: progressed_at)
    if is_latest_event
      check_job_status_error = update_check_run_state(check_job_status)
      unless check_job_status_error
        self.title = title
      end
    end

    save! unless check_job_status_error
  end

  private

  # Insert a log line into the check run's `text` field at the correct position based on its `progressed_at` timestamp.
  # The stored line is formatted as "[<timestamp>] <log_message>".
  # Returns true if the log message is the most recent (latest) entry, false otherwise.
  sig { params(log_message: String, progressed_at: Time).returns(T::Boolean) }
  def insert_log_into_text(log_message, progressed_at:)
    log_line = "[#{progressed_at.utc.iso8601(6)}] #{log_message}"

    if text.blank?
      self.text = log_line
      true
    else
      # The new timestamp is likely to be newer than existing timestamps. We start looking for the insert position from the end of the list and stop as soon as we find an older timestamp.
      lines = text.lines.map(&:chomp)
      insert_index = lines.length

      while insert_index > 0
        existing_ts = CheckRun::LicenseComplianceDependency.extract_timestamp(lines[insert_index - 1])
        break unless existing_ts && existing_ts > progressed_at
        insert_index -= 1
      end

      lines.insert(insert_index, log_line)
      self.text = lines.join("\n")

      insert_index == lines.length - 1
    end
  end

  sig { params(check_job_status: Integer).returns(T::Boolean) }
  def update_check_run_state(check_job_status)
    check_job_status_error = false

    case check_job_status
    when Hydro::Schemas::Github::Dependencygraph::V1::Entities::CheckJobStatus::CHECK_JOB_STATUS_STARTING
      self.status = :queued
      self.conclusion = nil
      self.completed_at = nil
      self.title = nil
    when Hydro::Schemas::Github::Dependencygraph::V1::Entities::CheckJobStatus::CHECK_JOB_STATUS_WAITING, Hydro::Schemas::Github::Dependencygraph::V1::Entities::CheckJobStatus::CHECK_JOB_STATUS_RUNNING
      self.status = :in_progress
      self.conclusion = nil
      self.completed_at = nil
      self.title = nil
    when Hydro::Schemas::Github::Dependencygraph::V1::Entities::CheckJobStatus::CHECK_JOB_STATUS_PASS,
         Hydro::Schemas::Github::Dependencygraph::V1::Entities::CheckJobStatus::CHECK_JOB_STATUS_FAIL
      self.status = :completed
      self.conclusion = :success
    when Hydro::Schemas::Github::Dependencygraph::V1::Entities::CheckJobStatus::CHECK_JOB_STATUS_ERROR
      self.status = :completed
      self.conclusion = :failure
    else
      check_job_status_error = true
      log_warning(
        reason: "unknown_check_job_status",
        message: "Received unknown check job status",
        function: "update_check_run_state",
        context: { "check_job_status" => check_job_status },
      )
    end

    check_job_status_error
  end

  sig { params(reason: String, message: String, function: String, context: T::Hash[String, T.untyped]).void }
  def log_warning(reason:, message:, function:, context: {})
    GitHub.dogstats.increment(
      "license_compliance.check_run.error",
      tags: ["reason:#{reason}"],
    )
    GitHub.logger.warn(
      message,
      { "code.namespace" => "CheckRun::LicenseComplianceDependency", "code.function" => function }.merge(context),
    )
  end
end
