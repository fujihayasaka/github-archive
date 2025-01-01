# typed: strict
# frozen_string_literal: true

module Exemptions
  class ExemptionRequest < ApplicationRecord::Repositories
    include Sequence::Context
    include Instrumentation::Model

    include ::Repositories::BelongsToRepository
    flagged_belongs_to_repository_via_domain optional: true
    belongs_to :resource_owner, polymorphic: true
    belongs_to :owner, class_name: "User"
    belongs_to :business
    belongs_to :requester, class_name: "User"
    has_many :responses, class_name: "Exemptions::ExemptionResponse", dependent: :destroy

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

      return where(business: source.business, owner: source)
      .joins("
        INNER JOIN repository_rule_suite_source_results
        ON repository_rule_suite_source_results.repository_rule_suite_id = exemption_requests.resource_owner_id
        AND repository_rule_suite_source_results.source_id = #{source.id}
        AND repository_rule_suite_source_results.source_type = 'User'") if source.is_a?(Organization)

      where(business: source)
      .joins("
        INNER JOIN repository_rule_suite_source_results
        ON repository_rule_suite_source_results.repository_rule_suite_id = exemption_requests.resource_owner_id
        AND repository_rule_suite_source_results.source_id = #{source.id}
        AND repository_rule_suite_source_results.source_type = 'Business'") if source.is_a?(Business)
    }

    scope :for_source_and_request_type, ->(source, request_type) {
      if request_type == SecretScanning::Constants::EXEMPTION_REQUEST_TYPE
        for_source(source)
      else
        for_ruleset_source(source)
      end
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

      ExemptionRequestEmailJob.perform_later(self)
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

      # Webhook instrumentation
      instrument event, prefix: "exemption_request", exemption_request_id: id, request_type: request_type
      # Hydro instrumentation
      GlobalInstrumenter.instrument("exemption_request.#{event}",
        exemption_request: self,
        actor: requester,
      )
    end
  end
end
