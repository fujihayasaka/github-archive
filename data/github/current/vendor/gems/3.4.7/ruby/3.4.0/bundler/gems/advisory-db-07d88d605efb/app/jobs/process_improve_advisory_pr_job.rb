# frozen_string_literal: true

class ProcessImproveAdvisoryPRJob < ApplicationJob
  queue_as :high

  MalformedAPIFileContent = Class.new(StandardError)
  ProcessImproveAdvisoryPRError = Class.new(StandardError)

  # If we get an error from Octokit or a currupt file blob from the API, odds are good there's a problem w/dotcom.
  # Let's retry a few times before erroring out!
  retry_on Octokit::Error, wait: :polynomially_longer
  retry_on MalformedAPIFileContent, wait: :polynomially_longer

  ERROR_BAD_JSON = "We were unable to parse this file's JSON! Please check your file syntax and try again."
  ERROR_GENERIC = "An error has occurred! We're looking into it."
  ERROR_GHSAS_DONT_MATCH = "The GHSA ID provided doesn't match the file you are editing. Please clarify which advisory you'd like to improve."
  ERROR_NO_FILES = "No advisory improvement file was found for this PR."
  ERROR_NO_SIGNIFICANT_CHANGES = "This PR does not contain any significant changes to the advisory."
  ERROR_TOO_MANY_FILES = "We only accept one advisory per PR. To improve other advisories, please open separate PRs."
  ERROR_TOO_MANY_PRS = "You already have a pending improvement for this advisory, please push updates to that PR instead."
  ERROR_UNABLE_TO_MATCH = "We were unable to match this file to an existing advisory."

  CHECK_RUN_SUCCESS_TITLE = "Processed advisory improvement"
  CHECK_RUN_SUCCESS_SUMMARY = "Thank you for contributing to GitHub's Advisory Database. Our Security Lab team will review your suggested advisory improvement for publication."
  CHECK_RUN_FAILURE_TITLE = "Could not process advisory improvement"

  def perform(pr_number:, head_sha:, actor_login:, actor_id:, check_run_id: nil)
    ::GitHub::Telemetry::Logs.logger.info(
      "Performing ProcessImproveAdvisoryPRJob",
      {
        "gh.advisory_inbox.pr_number": pr_number,
        "gh.advisory_inbox.head_sha": head_sha,
        "gh.advisory_inbox.actor_id": actor_id,
        "gh.advisory_inbox.check_run_id": check_run_id,
      },
    )
    check_run = if check_run_id.present?
                  CheckRun.find(check_run_id)
                else
                  CheckRun.create!(head_sha)
                end

    file_path = get_pr_file_path(pr_number)
    file_json = get_file_json(head_sha, file_path)

    import_pr_data(pr_number, file_path, file_json, actor_login, actor_id)

    check_run = check_run.success!(CHECK_RUN_SUCCESS_TITLE, CHECK_RUN_SUCCESS_SUMMARY)
  rescue ProcessImproveAdvisoryPRError => error
    ::GitHub::Telemetry::Logs.logger.error(
      "ProcessImproveAdvisoryPRError occurred",
      {
        exception: error,
        "gh.advisory_inbox.pr_number": pr_number,
        "gh.advisory_inbox.head_sha": head_sha,
        "gh.advisory_inbox.actor_id": actor_id,
        "gh.advisory_inbox.check_run_id": check_run_id,
      },
    )
    check_run = check_run.failure!(CHECK_RUN_FAILURE_TITLE, error.message)
  ensure
    if check_run&.incomplete?
      ::GitHub::Telemetry::Logs.logger.error(
        "CheckRun was incomplete by the time hook performance finished.",
        {
          "gh.advisory_inbox.pr_number": pr_number,
          "gh.advisory_inbox.head_sha": head_sha,
          "gh.advisory_inbox.actor_id": actor_id,
          "gh.advisory_inbox.check_run_id": check_run_id,
        },
      )
      check_run.failure!(CHECK_RUN_FAILURE_TITLE, ERROR_GENERIC)
    end
  end

  class CheckRun
    attr_reader :created_run, :completed_run

    def self.create!(head_sha)
      run = AdvisoryDB.github.create_check_run(
        AdvisoryDB.github_advisories_repo,
        "Processing advisory improvement",
        head_sha,
        status: "in_progress",
        started_at: Time.current,
      )

      new(run)
    end

    def self.find(check_run_id)
      run = AdvisoryDB.github.check_run(
        AdvisoryDB.github_advisories_repo,
        check_run_id,
      )

      new(run)
    end

    def initialize(created_run, completed_run = nil)
      @created_run = created_run
      @completed_run = completed_run
    end

    def incomplete?
      completed_run.nil?
    end

    def success!(title, description)
      complete_run(true, title, description)
    end

    def failure!(title, description)
      complete_run(false, title, description)
    end

    private

    def complete_run(successful, title, summary)
      conclusion = successful ? "success" : "failure"
      completed_run = AdvisoryDB.github.update_check_run(
        AdvisoryDB.github_advisories_repo,
        created_run.id,
        status: "completed",
        conclusion: conclusion,
        completed_at: Time.current,
        output: {
          title: title,
          summary: summary,
        },
      )

      self.class.new(created_run, completed_run)
    end
  end

  private

  def get_pr_file_path(pr_number)
    files = AdvisoryDB.github.pull_request_files(
      AdvisoryDB.github_advisories_repo,
      pr_number,
    )

    if files.empty?
      raise ProcessImproveAdvisoryPRError, ERROR_NO_FILES
    elsif files.length > 1
      raise ProcessImproveAdvisoryPRError, ERROR_TOO_MANY_FILES
    end

    file_path = files.first["filename"]
    ghsa_id = ghsa_id_from_file_path(file_path)

    unless ghsa_id && Advisory.exists?(ghsa_id: ghsa_id)
      raise ProcessImproveAdvisoryPRError, ERROR_UNABLE_TO_MATCH
    end

    file_path
  end

  def get_file_json(sha, path)
    file = AdvisoryDB.github.content(
      AdvisoryDB.github_advisories_repo,
      ref: sha,
      path: path,
    )

    begin
      blob = Base64.decode64(file.content).force_encoding(::Encoding::UTF_8)
      # ArgumentError/NoMethodError are generic so wrap the specific line to capture malformed API response
    rescue ArgumentError, NoMethodError
      raise MalformedAPIFileContent
    end

    JSON.parse(blob)
  rescue JSON::ParserError
    raise ProcessImproveAdvisoryPRError, ERROR_BAD_JSON
  end

  def import_pr_data(pr_number, file_path, json, actor_login, actor_id)
    data = AdvisoryImprovementData.create_from_improve_advisory_pr_json(
      pr_number: pr_number,
      json: json,
      actor_login: actor_login,
      actor_id: actor_id,
    )

    if data.ghsa_id != ghsa_id_from_file_path(file_path)
      raise ProcessImproveAdvisoryPRError, ERROR_GHSAS_DONT_MATCH
    end

    if import_would_orphan_existing_pr?(data.identifier, pr_number)
      raise ProcessImproveAdvisoryPRError, ERROR_TOO_MANY_PRS
    end

    if import_contains_no_significant_changes?(data)
      raise ProcessImproveAdvisoryPRError, ERROR_NO_SIGNIFICANT_CHANGES
    end

    AdvisoryImprovementImporter.new(advisory_improvement_data: data).import
  rescue AdvisoryDBToolkit::OSV::Transform::Error => error
    raise ProcessImproveAdvisoryPRError, error.message
  end

  def ghsa_id_from_file_path(file_path)
    File.basename(file_path)[/\b(GHSA-[\w-]+)\./, 1]
  end

  def import_would_orphan_existing_pr?(identifier, pr_number)
    existing_feed_entry = FeedEntry.find_by(identifier: identifier)
    return false unless existing_feed_entry

    existing_pr_number = existing_feed_entry.raw_payload["pr_number"]
    return false if existing_pr_number == pr_number

    existing_pr = AdvisoryDB.github.pull_request(
      AdvisoryDB.github_advisories_repo,
      existing_pr_number,
    )

    existing_pr.state == "open"
  end

  def import_contains_no_significant_changes?(data)
    advisory_review = AdvisoryReview.find_by(ghsa_id: data.ghsa_id)
    changes = data.advisory_payload_changes(advisory_review: advisory_review)
    changes.empty?
  end
end
