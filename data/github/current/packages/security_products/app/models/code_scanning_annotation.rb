# typed: true
# frozen_string_literal: true

class CodeScanningAnnotation < ApplicationRecord::Domain::RepositoriesActionsChecks
  self.table_name = "code_scanning_alerts"

  belongs_to :check_annotation
  belongs_to :check_run
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain

  scope :for_annotations, ->(annotations) { where(check_annotation: annotations) }

  validate :matches_check_run_repository
  validate :matches_check_annotation_repository

  # Get the distinct set of check run ids for the given alert numbers and
  # repository.
  #
  # Returns an array of check run ids.
  def self.check_run_ids(alert_numbers:, repository:)
    where(repository: repository).where(alert_number: alert_numbers).pluck(Arel.sql("DISTINCT check_run_id"))
  end

  # Load a set of Turboscan results for the alerts associated with given
  # annotation ids.
  #
  # Returns a hash where the keys are check annotation ids and the values are a
  # hash containing the alert results from Turboscan with the corresponding pull
  # request ref.
  def self.results_by_id(repository:, annotations:)
    code_scanning_annotations = for_annotations(annotations).where(repository: repository).preload(:check_run).to_a
    return {} if code_scanning_annotations.empty?

    check_suite_ids = code_scanning_annotations.map { |a| a.check_run&.check_suite_id }.compact.uniq
    cscs_by_cs_id = CodeScanningCheckSuite.for_check_suites(check_suite_ids, repository.id).index_by(&:check_suite_id)

    head_commit_oid = analysis_commit_oid(cscs_by_cs_id.values, "head") do |cscs|
      cscs.check_suite.head_sha
    end
    merge_commit_oid = analysis_commit_oid(cscs_by_cs_id.values, "merge") do |cscs|
      cscs.pull_request_sha.presence
    end

    if head_commit_oid.nil? && merge_commit_oid.nil?
      GitHub.logger.info(
        "No head or merge commit found",
        "code.function" => "results_by_id",
        "gh.repo.id" => repository.id,
        "gh.check_suite.ids" => check_suite_ids,
        "gh.code_scanning.check_suites" => cscs_by_cs_id.values.map(&:id),
        "gh.annotations" => annotations,
        "gh.freno.replication_delay" => Freno.client.replication_delay(store_name: CodeScanningCheckSuite.throttler_cluster_name),
      )
      return {}
    end

    # Fetch all the annotation results from turboscan for the alert numbers
    results = GitHub::Turboscan.annotations(
      repository_id: repository.id,
      numbers: code_scanning_annotations.map(&:alert_number),
      head_commit_oid: head_commit_oid,
      merge_commit_oid: merge_commit_oid,
    )&.data&.results || []

    # Build a hash of check annotation ids to code scanning annotations and, where available, results with the corresponding PR ref
    results_by_alert_number = results.index_by { |r| r.result.number }
    code_scanning_annotations.each_with_object({}) do |cs_annotation, hash|
      result = results_by_alert_number[cs_annotation.alert_number]

      hash[cs_annotation.check_annotation_id] = {
        cs_annotation: cs_annotation,
        result: result,
        pull_request_refs: result.present? ? cscs_by_cs_id[T.must(cs_annotation.check_run).check_suite_id]&.refs : nil
      }
    end
  end

  private_class_method def self.analysis_commit_oid(code_scanning_check_suites, block_identifier, &block)
    commit_oids = code_scanning_check_suites.map(&block).uniq
    return commit_oids[0] if commit_oids.length == 1
    GitHub.logger.info(
      "No single commit oid found",
      "gh.code_scanning.block_identifier" => block_identifier,
      "code.function" => "analysis_commit_oid",
      "gh.code_scanning.check_suites" => code_scanning_check_suites.map(&:id),
      "git.commit.oids" => commit_oids,
    )
    nil
  end

  private

  def matches_check_run_repository
    cr = check_run
    return if cr.nil?
    if repository_id != cr.repository_id
      errors.add(:repository, "does not match the check run's repository")
    end
  end

  def matches_check_annotation_repository
    ca = check_annotation
    return if ca.nil?
    if repository_id != ca.repository_id
      errors.add(:repository, "does not match the check annotation's repository")
    end
  end
end
