# typed: strict
# frozen_string_literal: true

module Exemptions
  class ExemptionRequest < ApplicationRecord::Repositories
    include Sequence::Context
    include Instrumentation::Model

    include ApplicationRecord::Sharding
    configure_sharding(sharding_key: :repository_id, should_shard: -> (_, _) { true })

    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain optional: true, legacy_return_type: true
    belongs_to :resource_owner, -> { annotate("cross-shard-query-exempted") }, polymorphic: true
    belongs_to :owner, class_name: "User"
    belongs_to :business
    belongs_to :requester, class_name: "User"
    has_many :responses, -> (request) { where(repository_id: request.repository_id) },
     class_name: "Exemptions::ExemptionResponse", dependent: :destroy
    has_one :latest_response, -> { order(created_at: :desc) }, class_name: "Exemptions::ExemptionResponse"

    validates_presence_of :request_type, :resource_owner, :requester
    before_validation :set_owner_and_business
    validates_presence_of :owner, if: -> { T.unsafe(self).repository.present? }
    validate :valid_requester
    validate :valid_status

    before_create :set_default_expiration
    before_create :set_number
    after_create_commit :send_notifications
    after_commit :instrument_event, only: [:create, :update]

    scope :not_expired, -> { where("expires_at > ?", Time.now) }

    scope :for_source, ->(source) {
      return where(repository_id: source.id) if source.is_a?(Repository)
      return where(business: source.business, owner: source) if source.is_a?(Organization)
      where(business: source) if source.is_a?(Business)
    }

    scope :for_ruleset_source, ->(source) {
      return where(repository_id: source.id) if source.is_a?(Repository)

      if source.is_a?(Organization)
        source_scope = where(business: source.business, owner: source, created_at: 1.month.ago..).order(created_at: :desc)
        source_type = "User"
      elsif source.is_a?(Business)
        source_scope = where(business: source, created_at: 1.month.ago..).order(created_at: :desc)
        source_type = "Business"
      else
        next
      end

      resource_owner_ids_filtered_by_source_result = []
      source_scope.pluck(:resource_owner_id).each_slice(10_000) do |resource_owner_id_batch|
        resource_owner_ids_filtered_by_source_result << RuleEngine::RuleSuiteSourceResult.where(
          repository_rule_suite_id: resource_owner_id_batch,
          source_id: source.id,
          source_type: source_type,
        )
        .annotate("cross-shard-query-exempted")
        .pluck(:repository_rule_suite_id)
      end

      source_scope.where(
        resource_owner_id: resource_owner_ids_filtered_by_source_result.take(50_000),
        resource_owner_type: "RuleEngine::RuleSuite"
      )
    }

    scope :for_source_and_request_type, ->(source, request_type) {
      if request_type == SecretScanning::Constants::EXEMPTION_REQUEST_TYPE
        for_source(source)
      else
        for_ruleset_source(source)
      end
    }

    scope :pending_bypass_requests_for_operation, ->(repository, operation) {
      # do this in 2 queries since they will soon be on separate clusters and cannot be joined
      requests = self.where(
        status: "pending",
        request_type: "repository_policy_ruleset_bypass",
        repository_id: repository.id,
        resource_owner_type: "RuleEngine::RuleSuite")

      rule_suite_ids = RuleEngine::EventActionRepositoryOperation.where(
          operation: operation,
          repository_id: repository.id)
        .joins("
          INNER JOIN repository_rule_suites
          ON repository_rule_suites.event_action_id = event_action_repository_operations.id
          AND repository_rule_suites.repository_id = event_action_repository_operations.repository_id")
        .where("repository_rule_suites.id IN (?)", requests.map(&:resource_owner_id))
        .pluck("repository_rule_suites.id")

      requests.select { |request| rule_suite_ids.include?(request.resource_owner_id) }
    }

    REQUEST_EVALUATORS = T.let([
      Evaluators::RepositoryPolicyRulesetBypass.new,
      Evaluators::PushRulesetBypass.new,
      Evaluators::SecretScanningBypass.new,
      Evaluators::CodeScanningAlertDismissal.new,
      Evaluators::SecretScanningClosureRequestBypass.new
    ].freeze, T::Array[ExemptionEvaluator])

    STATUSES = T.let({
      deleted: -1,
      pending: 0,
      completed: 1,
      rejected: 2,
      cancelled: 3,
      approved: 4,
    }.with_indifferent_access.freeze, T::Hash[T.any(Symbol, String), Integer])
    enum :status, STATUSES, default: :pending

    sig { void }
    def set_owner_and_business
      return if repository.nil?

      # owner_id defaults to 0, but business_id default to nil
      self.owner_id = T.must(repository).owner_id if self.owner_id == 0
      self.business_id ||= T.must(repository).owner&.business&.id
    end

    sig { returns(ExemptionEvaluator::EvaluationResult) }
    def compute_status
      return ExemptionEvaluator::EvaluationResult::Pending unless (eval_impl = evaluator)

      responses = self.responses.to_a
      eval_impl.evaluate(self, responses)
    end

    sig { returns(String) }
    def sequence_context_type
      T.must(self.class.name)
    end

    sig { returns(T.nilable(Integer)) }
    def sequence_context_id
      repository_id
    end

    sig { returns(T.nilable(ExemptionEvaluator)) }
    def evaluator
      REQUEST_EVALUATORS.find { |evaluator| evaluator.request_type == request_type }
    end

    sig { params(reviewer: User).returns(T::Boolean) }
    def is_valid_reviewer?(reviewer)
      @is_valid_reviewer ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
      @is_valid_reviewer[reviewer.id] ||= evaluator&.is_valid_reviewer?(self, reviewer) || false
    end

    sig { params(reviewer: User).returns(T::Boolean) }
    def has_undismissed_review?(reviewer)
      @has_undismissed_review ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
      @has_undismissed_review[reviewer.id] ||= responses.any? do |response|
        (response.reviewer == reviewer) && (response.status != "dismissed")
      end
    end

    sig { returns(T::Boolean) }
    def has_undismissed_review_by_any_reviewer?
      responses.any? do |response|
        response.status != "dismissed"
      end
    end

    sig { returns(T::Boolean) }
    def post_approval_action?
      evaluator&.post_approval_action?(self) || false
    end

    sig { returns(T.nilable(String)) }
    def post_approval_redirect_url
      evaluator&.post_approval_redirect_url(self)
    end

    sig { void }
    def valid_requester
      # presence validation is run separately
      return unless self.requester
      result, error = evaluator&.is_valid_requester?(self, T.must(self.requester))
      unless result
        errors.add(:requester, error || "is invalid")
      end
    end

    sig { void }
    def valid_status
      errors.add(:status, "is invalid") if status == "deleted"
    end

    sig { returns(T::Boolean) }
    def expired?
      Time.zone.now > expires_at
    end

    sig { returns(T.nilable(Types::ExemptionRequestDataHash)) }
    def exemption_data_hash
      evaluator&.exemption_data_hash(self)
    end

    sig { returns(T.nilable(String)) }
    def permalink
      evaluator&.permalink(self)
    end

    private

    sig { void }
    def set_number
      return unless repository_id.present?

      unless Sequence.exists?(self)
        Sequence.create(self)
      end
      self.number = Sequence.next(self)
    end

    sig { void }
    def set_default_expiration
      unless self.expires_at
        self.expires_at = Time.zone.now + 1.week
      end
    end

    sig { void }
    def send_notifications
      return unless ExemptionRequestEmailJob::PERFORM_REQUEST_TYPES.include?(request_type)

      ExemptionRequestEmailJob.perform_later(id:, repository_id:)
    end

    sig { void }
    def instrument_event
      event = if previous_changes.key?("id")
        # This is a creation event
        :create
      elsif status == "cancelled"
        :cancel
      elsif status == "completed"
        :complete
      end

      return unless event

      instrument_data = {
        prefix: "exemption_request",
        exemption_request_id: id,
        request_type: request_type,
        repository_id: repository_id
      }

      # Webhook instrumentation
      instrument event, **instrument_data
      # Hydro instrumentation
      GlobalInstrumenter.instrument("exemption_request.#{event}",
        exemption_request: self,
        actor: requester,
      )
    end
  end
end
