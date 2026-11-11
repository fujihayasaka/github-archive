# typed: strict
# frozen_string_literal: true

require "csv"

module SecurityProductsEnablement
  class CodeScanningAssessment < ApplicationRecord::Domain::SecurityProductsEnablement
    include Instrumentation::Model

    ERROR_FAILED_TO_CREATE = "Failed to create assessment"
    COOLDOWN_DAYS = 90

    class SequenceContext
      include Sequence::Context

      sig { returns(Integer) }
      attr_reader :owner_id

      sig { params(owner_id: Integer).void }
      def initialize(owner_id)
        @owner_id = owner_id
      end

      sig { returns(String) }
      def sequence_context_type = "SecurityProductsEnablement::CodeScanningAssessment"

      sig { returns(Integer) }
      def sequence_context_id = owner_id
    end

    belongs_to :owner, class_name: "::Organization", foreign_key: :owner_id, inverse_of: false
    belongs_to :requested_by, class_name: "::User", foreign_key: :requested_by_id, inverse_of: false

    has_many :assessment_repositories,
      class_name: "SecurityProductsEnablement::CodeScanningAssessmentRepository",
      foreign_key: :assessment_id,
      inverse_of: :assessment,
      dependent: :destroy

    has_many :assessment_results,
      class_name: "SecurityProductsEnablement::CodeScanningAssessmentResult",
      foreign_key: :assessment_id,
      inverse_of: :assessment,
      dependent: :destroy

    validates :owner_id, presence: true
    validates :requested_by_id, presence: true
    validates :number, presence: true, uniqueness: { scope: :owner_id }
    validates :status, presence: true

    after_commit :send_status_email, if: :should_send_status_email?

    enum :status, {
      pending: 0,
      completed: 2,
      failed: 3
    }, validate: true

    # Struct for serialized assessment results
    class AssessmentResultsPayload < T::Struct
      const :status, String
      const :number, Integer
      const :created_at, Time
      const :total_vulnerabilities, Integer
      const :total_selected_repositories, Integer
      const :total_org_repositories, Integer
      const :repositories_scanned, T::Array[CodeScanningAssessmentResult::RepositoryStats]
      const :vulnerabilities_by_language, T::Array[CodeScanningAssessmentResult::LanguageVulnerabilities]
      const :rules_detected, T::Array[CodeScanningAssessmentResult::DetectedRuleStats]
      const :can_request_another_assessment, T::Boolean
      const :next_request_available_at, T.nilable(Time)

      sig { params(_options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def as_json(_options = nil)
        {
          status:,
          number:,
          created_at: created_at.iso8601,
          total_vulnerabilities:,
          total_selected_repositories:,
          total_org_repositories:,
          repositories_scanned: repositories_scanned.map(&:to_hash),
          vulnerabilities_by_language: vulnerabilities_by_language.map(&:to_hash),
          rules_detected: rules_detected.map(&:to_hash),
          top_rules: rules_detected.first(3).map(&:to_hash), # TODO: remove once frontend migrates to rules_detected
          can_request_another_assessment:,
          next_request_available_at: next_request_available_at&.iso8601,
        }
      end
    end

    # Whether a new assessment can be requested.
    # - Failed assessments: always allow (skip cooldown check)
    # - Completed assessments with no successful repos: treat as failed (allow retry)
    # - Pending assessments: never allow (assessment is in progress)
    # - Completed assessments: allow only if cooldown period has elapsed
    sig { returns(T::Boolean) }
    def can_request_another_assessment?
      return true if failed?
      return true if all_repos_unsuccessful?
      return false if pending?
      created_at < COOLDOWN_DAYS.days.ago
    end

    # True when the assessment is recorded as completed but every repository
    # either timed out or failed — i.e. no repo produced usable results.
    # These assessments should be treated as failures for cooldown purposes
    # so the user can immediately request another run.
    sig { returns(T::Boolean) }
    def all_repos_unsuccessful?
      return false unless completed?
      repos = assessment_repositories
      repos.any? && repos.all? { |r| %w[timed_out failed].include?(r.status) }
    end

    # The status to expose to UI consumers. Assessments where every repo was
    # unsuccessful are stored as "completed" in the DB but produced no results,
    # so we surface them as "failed" to avoid misleading UI (e.g. a
    # "no vulnerabilities" banner when nothing was actually scanned).
    sig { returns(String) }
    def effective_status
      return "failed" if all_repos_unsuccessful?
      status
    end

    # The time at which the cooldown expires and another assessment can be requested.
    # Applicable to completed and pending assessments within the cooldown window.
    # Returns nil for failed assessments or if the cooldown has already elapsed.
    sig { returns(T.nilable(Time)) }
    def cooldown_ends_at
      return nil if can_request_another_assessment?
      created_at + COOLDOWN_DAYS.days
    end

    sig { params(org: Organization).returns(T.nilable(AssessmentResultsPayload)) }
    def self.latest_results_for_org(org)
      assessment = where(owner_id: org.id).order(number: :desc).first
      return nil if assessment.nil?

      assessment.build_results_payload(
        can_request_another_assessment: assessment.can_request_another_assessment?,
        next_request_available_at: assessment.cooldown_ends_at
      )
    end

    CSV_INJECTION_CHARS = ["=", "+", "-", "@", ";"].freeze

    sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
    def self.sanitize_csv_field(value)
      return value if value.nil?

      stripped = value.lstrip
      return value unless CSV_INJECTION_CHARS.any? { |c| stripped.start_with?(c) }

      "'#{value}"
    end

    CSV_HEADERS = T.let([
      "Repository",
      "Status",
      "Rule ID",
      "Rule Name",
      "Language",
      "Severity",
      "Vulnerability Count",
      "Autofix Supported",
    ].freeze, T::Array[String])

    sig { returns(String) }
    def self.csv_header
      CSV.generate { |csv| csv << CSV_HEADERS }
    end

    sig { params(assessment: CodeScanningAssessment, org: Organization).returns(String) }
    def self.generate_results_csv(assessment:, org:)
      all_assessment_repos = assessment.assessment_repositories.to_a
      all_results = assessment.assessment_results.to_a

      all_repo_ids = all_assessment_repos.map(&:repository_id)
      repos_map = org.repositories.not_archived_scope.where(id: all_repo_ids).index_by(&:id)
      results_by_repo = all_results.group_by(&:repository_id)

      CSV.generate do |csv|
        csv << CSV_HEADERS

        all_assessment_repos.sort_by { |ar| repos_map[ar.repository_id]&.name.to_s }.each do |assessment_repo|
          repo = repos_map[assessment_repo.repository_id]
          next unless repo

          repo_name = sanitize_csv_field(repo.name)
          # Surface timed_out as "failed" to match the UI's status display.
          display_status = assessment_repo.timed_out? ? "failed" : assessment_repo.status
          status = sanitize_csv_field(display_status)
          repo_results = results_by_repo[assessment_repo.repository_id] || []

          if repo_results.empty?
            csv << [repo_name, status, nil, nil, nil, nil, nil, nil]
          else
            repo_results
              .sort_by { |r| [-(CodeScanningAssessmentResult::SEVERITY_ORDER[r.severity] || 0), r.rule_id] }
              .each do |result|
                csv << [
                  repo_name,
                  status,
                  sanitize_csv_field(result.rule_id),
                  sanitize_csv_field(result.rule_name),
                  sanitize_csv_field(result.language),
                  sanitize_csv_field(result.severity),
                  result.vulnerability_count,
                  result.autofix_supported,
                ]
              end
          end
        end
      end
    end

    sig do
      params(
        can_request_another_assessment: T::Boolean,
        next_request_available_at: T.nilable(Time),
      ).returns(AssessmentResultsPayload)
    end
    def build_results_payload(can_request_another_assessment:, next_request_available_at:)
      org = T.must(owner)
      total_org_repositories = org.repositories.not_archived_scope.count

      # If assessment is not completed, return minimal response with just status
      unless completed?
        return AssessmentResultsPayload.new(
          status: effective_status,
          number:,
          created_at:,
          total_vulnerabilities: 0,
          total_selected_repositories: assessment_repositories.count,
          total_org_repositories:,
          repositories_scanned: [],
          vulnerabilities_by_language: [],
          rules_detected: [],
          can_request_another_assessment:,
          next_request_available_at:,
        )
      end

      build_completed_results_payload(
        org:,
        total_org_repositories:,
        can_request_another_assessment:,
        next_request_available_at:,
      )
    end

    sig do
      params(
        org: Organization,
        actor: User,
        repository_ids: T::Array[Integer],
        marketing_info: T::Hash[Symbol, T.untyped],
      ).returns(T.nilable(String))
    end
    def self.create_assessment_for_org(org:, actor:, repository_ids:, marketing_info: {})
      validation = CodeScanningAssessmentRepository.validate_repository_ids(org, repository_ids)
      return validation.error unless validation.success?

      assessment = create_assessment_in_transaction(
        org:, actor:, valid_repo_ids: validation.valid_ids,
      )
      return ERROR_FAILED_TO_CREATE if assessment.nil?

      # Enqueue one trigger job per repository after the transaction commits
      # so that the assessment and repository rows are visible to the job worker.
      # NOTE: This assumes create_assessment_for_org is called at the top level
      # (e.g., from a controller action), not nested inside an outer transaction.
      # If it were wrapped in an outer transaction, perform_later would fire before
      # the outer transaction commits, and the worker could fail to find the rows.
      assessment.assessment_repositories.pluck(:id).each do |ar_id|
        TriggerCodeScanningAssessmentJob.perform_later(
          code_scanning_assessment_repository_id: ar_id,
        )
      end

      instrument_assessment_creation(assessment:, org:, actor:)

      begin
        enqueue_marketing_form_submission(org, actor, marketing_info)
      rescue StandardError => e
        GitHub.logger.error("error submitting marketing form", {
          "exception.message": e.message,
          "code.namespace": "SecurityProductsEnablement::CodeScanningAssessment",
          "code.function": "create_assessment_for_org",
          "gh.user.id": actor.id,
          "gh.organization.id": org.id,
        })
      end

      nil
    end

    sig { params(org: Organization, user: User, marketing_info: T::Hash[Symbol, T.untyped]).void }
    def self.enqueue_marketing_form_submission(org, user, marketing_info)
      return if GitHub.enterprise?
      return if user.staff_user? && !FeatureFlag.vexi.enabled?(FeatureFlags::CSRA_MARKETING_STAFF_BYPASS, org, default: false)

      return unless user.primary_user_email&.verified?
      return unless user.primary_user_email&.email.present?
      return unless user.primary_user_email&.email.match?(UserEmail::MarketingDependency::EMAIL_REGEX)
      return unless user.display_name.present?
      return unless org.profile_location.present?

      marketo_data = {
        name: user.display_name,
        email: user.primary_user_email&.email,
        country: org.profile_location,
        org_name: org.name,
        marketingConsent: nil,
        cDLProgramName: "512802",
        source: "In Product Interaction",
        sFDCLastCampaignStatus: "Responded",
        utm_campaign: marketing_info[:utm_campaign],
        utm_medium: marketing_info[:utm_medium],
        utm_source: marketing_info[:utm_source],
        utm_content: marketing_info[:utm_content],
      }.compact

      MarketingFormsSubmissionJob.perform_later(form_name: "code-security-risk-assessment-product-form", raw_data: marketo_data)
    end

    sig { void }
    def refresh_status!
      repos = assessment_repositories.reload

      self.status =
        if repos.empty?
          :pending
        elsif repos.all?(&:failed?)
          :failed
        elsif repos.all?(&:completed?)
          :completed
        else
          :pending
        end

      if status_changed?
        save!
        instrument :status_updated, {
          org: owner&.display_login,
          org_id: owner_id,
        }
      end
    end

    # Ensures a sequence counter exists for the given owner and is at least
    # as high as the current max number, so it won't collide with rows created
    # outside the sequence (e.g. factory-created test data or legacy records).
    # Follows the read/write split pattern from RepositoryVulnerabilityAlert.
    sig { params(owner_id: Integer).void }
    def self.ensure_sequence_exists(owner_id)
      context = SequenceContext.new(owner_id)

      # Short-circuit reads via replica (covers >99% of calls)
      unless ActiveRecord::Base.connected_to(role: :reading) { Sequence.exists?(context) }
        # Create if missing; no-ops via rescue RecordNotUnique if already exists on primary
        ActiveRecord::Base.connected_to(role: :writing) { Sequence.create(context) }
      end

      # Always bump on primary to avoid collisions with legacy/factory rows.
      # This is safe even under replica lag because create above ensures
      # the row exists on primary before we read/set it.
      ActiveRecord::Base.connected_to(role: :writing) do
        current_max = where(owner_id:).maximum(:number) || 0
        Sequence.set(context, current_max) if current_max > Sequence.get(context)
      end
    end

    # Returns the next assessment number for the given owner, atomically.
    sig { params(owner_id: Integer).returns(Integer) }
    def self.next_sequence_number(owner_id)
      ActiveRecord::Base.connected_to(role: :writing) { Sequence.next(SequenceContext.new(owner_id)) }
    end

    sig do
      params(
        org: Organization,
        actor: User,
        valid_repo_ids: T::Array[Integer],
      ).returns(T.nilable(CodeScanningAssessment))
    end
    def self.create_assessment_in_transaction(org:, actor:, valid_repo_ids:)
      assessment = T.let(nil, T.nilable(CodeScanningAssessment))

      ensure_sequence_exists(org.id)

      transaction do
        number = next_sequence_number(org.id)

        assessment = create!(
          owner_id: org.id,
          requested_by_id: actor.id,
          number:,
          status: :pending,
        )

        valid_repo_ids.each do |repo_id|
          CodeScanningAssessmentRepository.create!(
            assessment: assessment,
            repository_id: repo_id,
            status: :requested,
          )
        end
      end

      assessment
    rescue ActiveRecord::RecordInvalid
      nil
    end

    sig do
      params(
        assessment: CodeScanningAssessment,
        org: Organization,
        actor: User,
      ).void
    end
    def self.instrument_assessment_creation(assessment:, org:, actor:)
      audit_context = {
        org: org.display_login,
        org_id: org.id,
        actor: actor.display_login,
        actor_id: actor.id,
        code_scanning_risk_assessment_number: assessment.number,
      }

      assessment.instrument :create, audit_context

      # Preload repository to avoid N+1
      CodeScanningAssessmentRepository
        .where(assessment_id: assessment.id)
        .includes(:repository)
        .each do |repo_record|
          repo_record.instrument :create, audit_context
        end
    end

    private_class_method :create_assessment_in_transaction, :instrument_assessment_creation

    sig { returns(String) }
    def event_prefix
      "code_scanning_risk_assessment"
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def event_payload
      {
        code_scanning_risk_assessment_id: id,
        code_scanning_risk_assessment_number: number,
        code_scanning_risk_assessment_status: status,
        code_scanning_risk_assessment_created_at: created_at,
      }
    end

    private

    sig { returns(T::Boolean) }
    def should_send_status_email?
      (completed? || failed?) && saved_change_to_status?
    end

    sig { void }
    def send_status_email
      actor = requested_by
      return unless actor.present?

      org = owner
      return unless org.present?

      num_vulnerabilities = completed? ? assessment_results.sum(:vulnerability_count).to_i : 0

      ::CodeScanningAssessmentMailer.assessment_summary(
        actor,
        org,
        number,
        status,
        num_vulnerabilities:,
      ).deliver_later
    end

    sig do
      params(
        org: Organization,
        total_org_repositories: Integer,
        can_request_another_assessment: T::Boolean,
        next_request_available_at: T.nilable(Time),
      ).returns(AssessmentResultsPayload)
    end
    def build_completed_results_payload(org:, total_org_repositories:, can_request_another_assessment:, next_request_available_at:)
      # Load all data upfront (3 queries total, small datasets)
      all_assessment_repos = assessment_repositories.to_a
      all_results = assessment_results.to_a
      total_selected_repositories = all_assessment_repos.size

      all_repo_ids = all_assessment_repos.map(&:repository_id)

      # Only include repos that still belong to the org and are active/non-archived.
      repos_map = org.repositories.not_archived_scope.where(id: all_repo_ids).index_by(&:id)

      # Get completed repository IDs that are still valid (active, non-archived, in org)
      valid_completed_repo_ids = all_assessment_repos
        .select { |assessment_repo| assessment_repo.status == "completed" && repos_map.key?(assessment_repo.repository_id) }
        .map(&:repository_id)
        .to_set

      # Filter results to valid/completed repos only
      completed_results = all_results.select { |r| valid_completed_repo_ids.include?(r.repository_id) }

      # In-memory aggregations via CodeScanningAssessmentResult class methods
      AssessmentResultsPayload.new(
        status: effective_status,
        number:,
        created_at:,
        total_vulnerabilities: CodeScanningAssessmentResult.total_vulnerabilities(completed_results),
        total_selected_repositories:,
        total_org_repositories:,
        repositories_scanned: CodeScanningAssessmentResult.stats_by_repository(
          completed_results,
          assessment_repos: all_assessment_repos,
          repos_map:,
        ),
        vulnerabilities_by_language: CodeScanningAssessmentResult.vulnerabilities_by_language(completed_results),
        rules_detected: CodeScanningAssessmentResult.rules_detected(completed_results),
        can_request_another_assessment:,
        next_request_available_at:,
      )
    end
  end
end
