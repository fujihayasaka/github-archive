# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# CodeScanning::PullRequestCreatedJob will create the necessary code scanning check suites/runs
# if an analysis already exists when a pull request is opened.
# This can occur when a user has code scanning set up to run on:push, e.g:
#   * push some changes to a branch
#   * code scanning runs
#   * open a PR
class CodeScanning::PullRequestCreatedJob < ApplicationJob
  class TurboscanError < StandardError
    attr_reader :twirp_error

    def initialize(msg, twirp_error: nil)
      super(msg)
      @twirp_error = twirp_error
    end
  end

  class CreateCheckSuitesError < StandardError
  end

  use_primaries ApplicationRecord::RepositoriesActionsChecks

  retry_on TurboscanError, wait: :polynomially_longer do |job, error|
    Failbot.report(error, "gh.pull_request.id": job.pull_request_id, "gh.repo.id": job.repository_id, "gh.turboscan.twirp_error_code": error&.twirp_error&.to_s)
  end

  def pull_request_id
    arguments.first[:pull_request]&.id
  end

  def repository_id
    arguments.first[:pull_request]&.repository_id
  end

  queue_as :code_scanning

  before_perform do |job|
    Failbot.push(job: job.class.name)
  end

  retry_on_dirty_exit

  def self.should_perform?(pull_request:)
    pull_request&.repository&.code_scanning_enabled?
  end

  def self.enqueue_if_necessary(pull_request:)
    perform_later(pull_request: pull_request) if CodeScanning::PullRequestCreatedJob.should_perform?(pull_request: pull_request)
  end

  def perform(pull_request:)
    # Enqueue a job to update the pull request analysis status to disabled if we find this pull request has not been analyzed.
    CodeScanning::UpdatePullRequestEnablementJob.set(wait: Repository::CodeScanningDependency::PULL_REQUEST_ANALYSIS_TIME_LIMIT).perform_later(repository_id: pull_request.repository_id)

    # check if code scanning was disabled while waiting to start
    return unless CodeScanning::PullRequestCreatedJob.should_perform?(pull_request: pull_request)

    base_ref = pull_request.base_ref
    head_ref = pull_request.head_ref

    base_sha = pull_request.base_sha
    head_sha = pull_request.head_sha

    return if head_ref.blank?

    ref = "refs/heads/#{head_ref}"

    # check if Turboscan has an analysis
    response = GitHub::Turboscan.analyses(ref_names_bytes: [ref.b], repository_id: pull_request.repository_id)

    if response.nil? || response.data.nil? || response.error.present?
      raise TurboscanError.new("Turboscan GetAnalyses endpoint failed for PullRequestCreatedJob", twirp_error: response&.error)
    end

    return if T.must(response.data).total_count == 0

    matching = T.must(response.data).analyses.select { |analysis| analysis.commit_oid == head_sha }

    return unless matching.size > 0

    GitHub.logger.info(
      "Creating code scanning check suite for pull request",
      "code.namespace" => "CodeScanning::PullRequestCreatedJob",
      "code.function" => "perform",
      "gh.repo.id" => pull_request.repository_id,
      "gh.pull_request.base_sha" => base_sha,
      "gh.pull_request.base_ref" => base_ref,
      "gh.pull_request.head_sha" => head_sha,
      "gh.pull_request.head_ref" => head_ref,
      "gh.pull_request.id" => pull_request.id,
      "gh.pull_request.number" => pull_request.number,
    )

    code_scanning_check_suite = CheckRun.create_code_scanning_check_suite(
      repository: pull_request.repository,
      annotated_commit_oid: head_sha,
      analyzed_commit_oid: head_sha,
      ref: ref,
      base_ref: "refs/heads/#{base_ref}",
      base_sha: base_sha,
    )

    raise CreateCheckSuitesError.new("Failed to create code scanning check suite for PullRequestCreatedJob") if code_scanning_check_suite.nil?

    check_runs = CheckRun.create_code_scanning_check_runs(
      check_suite: code_scanning_check_suite.check_suite,
      tool_names: matching.map { |a| a.tool_description&.name },
    )

    check_runs.each do |check_run|
      CreateCodeScanningAnnotationsJob.perform_later(check_run_id: check_run.id, reason: :pr_opened)
    end
  end
end
