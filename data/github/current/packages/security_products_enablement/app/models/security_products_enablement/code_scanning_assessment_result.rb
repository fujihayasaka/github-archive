# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class CodeScanningAssessmentResult < ApplicationRecord::Domain::SecurityProductsEnablement
    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain class_name: "::Repository"

    belongs_to :assessment, class_name: "SecurityProductsEnablement::CodeScanningAssessment"
    VALID_SEVERITIES = T.let(%w[critical high medium low].freeze, T::Array[String])
    SEVERITY_ORDER = T.let({ "critical" => 4, "high" => 3, "medium" => 2, "low" => 1 }.freeze, T::Hash[String, Integer])

    validates :assessment, presence: true
    validates :repository, presence: true
    validates :rule_id, presence: true, uniqueness: { scope: [:assessment_id, :repository_id] }
    validates :rule_name, presence: true
    validates :language, presence: true
    validates :severity, presence: true, inclusion: { in: VALID_SEVERITIES }
    validates :vulnerability_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

    class LanguageVulnerabilities < T::Struct
      const :language, String
      const :count, Integer

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_hash
        { language:, count: }
      end
    end

    class DetectedRuleStats < T::Struct
      const :rule_id, String
      const :rule_name, T.nilable(String)
      const :severity, T.nilable(String)
      const :distinct_repos, Integer
      const :total_vulnerabilities, Integer

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_hash
        {
          rule_id:,
          rule_name:,
          severity:,
          distinct_repos:,
          total_vulnerabilities:,
        }
      end
    end

    class RepositoryStats < T::Struct
      const :repository_id, Integer
      const :name, String
      const :status, String
      const :total_vulnerability_count, Integer
      const :autofix_count, Integer
      const :code_security_enabled, T::Boolean

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_hash
        {
          repository_id:,
          name:,
          status:,
          total_vulnerability_count:,
          autofix_count:,
          code_security_enabled:,
        }
      end
    end

    # Aggregation methods for in-memory processing of result sets

    sig { params(results: T::Array[CodeScanningAssessmentResult]).returns(Integer) }
    def self.total_vulnerabilities(results)
      results.sum(&:vulnerability_count)
    end

    sig { params(results: T::Array[CodeScanningAssessmentResult]).returns(T::Array[LanguageVulnerabilities]) }
    def self.vulnerabilities_by_language(results)
      results
        .group_by(&:language)
        .map { |lang, items| LanguageVulnerabilities.new(language: lang, count: items.sum(&:vulnerability_count)) }
        .sort_by { |lv| -lv.count }
    end

    sig { params(results: T::Array[CodeScanningAssessmentResult]).returns(T::Array[DetectedRuleStats]) }
    def self.rules_detected(results)
      results
        .group_by(&:rule_id)
        .map do |rule_id, items|
          DetectedRuleStats.new(
            rule_id:,
            rule_name: items.first&.rule_name,
            severity: items.max_by { |r| severity_order(r.severity) }&.severity,
            distinct_repos: items.map(&:repository_id).uniq.size,
            total_vulnerabilities: items.sum(&:vulnerability_count),
          )
        end
        .sort_by { |tr| [-tr.total_vulnerabilities, tr.rule_id] }
    end

    # Builds per-repository vulnerability stats from results.
    # Note: Repositories that no longer exist (deleted after results were created)
    # are silently skipped via the repos_map lookup.
    sig do
      params(
        results: T::Array[CodeScanningAssessmentResult],
        assessment_repos: T::Array[CodeScanningAssessmentRepository],
        repos_map: T::Hash[Integer, ::Repository],
      ).returns(T::Array[RepositoryStats])
    end
    def self.stats_by_repository(results, assessment_repos:, repos_map:)
      by_repo = results.group_by(&:repository_id)

      code_security_map = repos_map.transform_values do |repo|
        CodeSecurity::Features::AdvancedSecurityHelper.code_security_features_usable?(repository: repo)
      end

      assessment_repos.filter_map do |assessment_repo|
        repo = repos_map[assessment_repo.repository_id]
        next unless repo

        repo_results = by_repo[assessment_repo.repository_id] || []
        total_count = repo_results.sum(&:vulnerability_count)
        autofix_count = repo_results.select(&:autofix_supported).sum(&:vulnerability_count)

        RepositoryStats.new(
          repository_id: assessment_repo.repository_id,
          name: repo.name,
          status: assessment_repo.status,
          total_vulnerability_count: total_count,
          autofix_count: autofix_count,
          code_security_enabled: code_security_map.fetch(assessment_repo.repository_id, false),
        )
      end.sort_by { |rs| -rs.total_vulnerability_count }
    end

    class << self
      private

      sig { params(severity: T.nilable(String)).returns(Integer) }
      def severity_order(severity)
        SEVERITY_ORDER.fetch(severity.to_s, 0)
      end
    end
  end
end
