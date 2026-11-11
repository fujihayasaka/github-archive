# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class CodeScanningAssessmentRepository < ApplicationRecord::Domain::SecurityProductsEnablement
    include ::Repositories::BelongsToRepository
    include Instrumentation::Model

    belongs_to_repository_via_domain class_name: "::Repository"

    belongs_to :assessment, class_name: "SecurityProductsEnablement::CodeScanningAssessment"

    validates :assessment, presence: true
    validates :repository, presence: true
    validates :repository_id, uniqueness: { scope: :assessment_id }
    validates :status, presence: true

    MAX_REPOSITORIES_PER_ASSESSMENT = 20
    NOT_COMPLETED_STATUSES = %w[ requested pending ]
    COMPLETED_STATUSES = %w[ timed_out failed completed ]
    STALE_DURATION = T.let(1.hour, ActiveSupport::Duration)
    PROCESSABLE_STATUSES = %w[ pending timed_out ]

    UPSERT_ON_DUPLICATE_SQL = T.let(
      Arel.sql(
        "rule_name=VALUES(rule_name), language=VALUES(language), " \
        "severity=VALUES(severity), autofix_supported=VALUES(autofix_supported), " \
        "vulnerability_count=VALUES(vulnerability_count), updated_at=VALUES(updated_at)"
      ),
      T.untyped,
    )

    class RepositoryValidationResult < T::Struct
      const :valid_ids, T::Array[Integer]
      const :error, T.nilable(String)

      sig { returns(T::Boolean) }
      def success?
        error.nil?
      end
    end

    enum :status, {
      requested: 0,
      pending: 1,
      completed: 2,
      timed_out: 3,
      failed: 4
    }, validate: true

    scope :not_completed, -> { where(status: NOT_COMPLETED_STATUSES) }
    scope :completed, -> { where(status: COMPLETED_STATUSES) }
    scope :stale, -> { not_completed.where("created_at < ?", STALE_DURATION.ago) }

    after_commit :refresh_assessment_status, on: :update, if: :status_previously_changed?
    after_commit :instrument_status_updated, on: :update, if: :status_previously_changed?

    sig { returns(T::Boolean) }
    def completed?
      COMPLETED_STATUSES.include?(status)
    end

    sig do
      params(
        assessment_id: Integer,
        repository_id: Integer,
        rules: T::Array[T::Hash[Symbol, T.untyped]],
        failure_reason: T.nilable(String),
      ).void
    end
    def self.apply_csra_results!(assessment_id:, repository_id:, rules:, failure_reason: nil)
      repo_row = find_by(assessment_id:, repository_id:)

      unless repo_row
        GitHub.logger.info(
          "security_products_enablement.csra_repo_row_not_found",
          assessment_id:,
          repository_id:,
        )
        return
      end

      unless repo_row.status.in?(PROCESSABLE_STATUSES)
        GitHub.logger.info(
          "security_products_enablement.csra_ignored_due_to_status",
          assessment_id:,
          repository_id:,
          status: repo_row.status,
        )
        return
      end

      transaction do
        if failure_reason.present?
          repo_row.update!(status: :failed, failure_reason: failure_reason)
        else
          rules.each do |rule|
            CodeScanningAssessmentResult.upsert(
              {
                assessment_id:,
                repository_id:,
                rule_id: rule.fetch(:rule_id),
                rule_name: rule.fetch(:rule_name),
                language: rule.fetch(:language),
                severity: rule.fetch(:severity),
                autofix_supported: rule.fetch(:autofix_supported, false),
                vulnerability_count: rule.fetch(:vulnerability_count, 0),
                created_at: Time.current,
                updated_at: Time.current,
              },
              on_duplicate: UPSERT_ON_DUPLICATE_SQL,
            )
          end

          repo_row.update!(status: :completed, failure_reason: nil)
        end
      end

      repo_row.instrument :results_received, {
        org: repo_row.assessment&.owner&.display_login,
        org_id: repo_row.assessment&.owner_id,
        code_scanning_risk_assessment_number: repo_row.assessment&.number,
        code_scanning_risk_assessment_repository_status: repo_row.status,
      }
    end

    # Validates repository IDs: deduplicates, checks max count, and verifies org membership.
    sig do
      params(
        org: Organization,
        repository_ids: T::Array[Integer],
      ).returns(RepositoryValidationResult)
    end
    def self.validate_repository_ids(org, repository_ids)
      ids = repository_ids.uniq

      if ids.empty?
        return RepositoryValidationResult.new(valid_ids: [], error: "No valid repositories provided")
      end

      if ids.size > MAX_REPOSITORIES_PER_ASSESSMENT
        return RepositoryValidationResult.new(
          valid_ids: [],
          error: "Cannot select more than #{MAX_REPOSITORIES_PER_ASSESSMENT} repositories",
        )
      end

      valid_ids = ::Repository
        .where(id: ids, owner_id: org.id)
        .pluck(:id)

      if valid_ids.empty?
        return RepositoryValidationResult.new(valid_ids: [], error: "No valid repositories provided")
      end

      RepositoryValidationResult.new(valid_ids:, error: nil)
    end

    sig { returns(String) }
    def event_prefix
      "code_scanning_risk_assessment_repository"
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def event_payload
      {
        code_scanning_risk_assessment_repository_id: id,
        code_scanning_risk_assessment_repository_created_at: created_at,
        code_scanning_risk_assessment_id: assessment_id,
        repo: repository&.name_with_display_owner,
        repo_id: repository_id,
      }
    end

    private

    sig { void }
    def refresh_assessment_status
      assessment&.refresh_status!
    end

    sig { void }
    def instrument_status_updated
      instrument :status_updated, {
        org: assessment&.owner&.display_login,
        org_id: assessment&.owner_id,
        code_scanning_risk_assessment_number: assessment&.number,
        code_scanning_risk_assessment_repository_status: status,
      }
    end
  end
end
