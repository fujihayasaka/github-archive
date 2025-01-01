# typed: true
# frozen_string_literal: true

module RuleEngine
  class PullRequestReviewRule
    class Decision
      extend T::Sig

      attr_reader :ref_update, :rules_fulfilled, :reason, :instrumentation_payload, :rule_decisions,
        :considered_pull_request_ids, :compliant_pull_request_ids

      sig { returns(T::Hash[PullRequestReview, Symbol]) }
      attr_reader :review_statuses

      def initialize(ref_update, rules_fulfilled, reason:, instrumentation_payload: {})
        @ref_update = ref_update
        @rules_fulfilled = rules_fulfilled
        @reason = Reason.new(**reason)
        @instrumentation_payload = instrumentation_payload
        @rule_decisions = {}
        @considered_pull_request_ids = []
        @compliant_pull_request_ids = []
        @review_statuses = {}
      end

      # Public: Create a successful Decision for PullRequestReview
      def self.success(ref_update, reason:, instrumentation_payload: nil)
        new(ref_update, true, reason: reason, instrumentation_payload: instrumentation_payload)
      end

      def add_rule_decision(rule_config, decision)
        @rule_decisions[rule_config] = decision
      end

      # TODO: Replace this method with use of `review_statuses` and stop reloading reviews
      # This will be easier to do once the old non-strict PR rule class is removed
      # Return all the enforced PullRequestReview involved in determining this Decision.
      #
      # Returns Array of PullRequestReview
      def reviews
        return @reviews if defined?(@reviews)
        @reviews = PullRequestReview.find(instrumentation_payload[:review_ids])
      end

      alias_method :rules_fulfilled?, :rules_fulfilled

      def more_reviews_required?
        !!instrumentation_payload[:approving_reviews_required] || code_owner_review_required? || soc2_approval_process_required?
      end

      def code_owner_review_required?
        !!instrumentation_payload[:code_owner_review_required]
      end

      def thread_resolution_required?
        !!instrumentation_payload[:thread_resolution_required]
      end

      def soc2_approval_process_required?
        !!instrumentation_payload[:soc2_approval_process_required]
      end

      def has_reviews?
        !!instrumentation_payload[:review_ids]&.any?
      end

      def has_approving_reviews?
        instrumentation_payload[:approving_reviews_count].to_i > 0
      end

      def approved?
        case reason.code
        when :review_policy_not_required
          has_approving_reviews?
        when :review_policy_not_satisfied
          false
        when :review_approved
          true
        end
      end

      def changes_requested?
        !!instrumentation_payload[:has_requested_changes]
      end

      class Reason
        attr_reader :code, :summary, :message, :instrumentation_payload

        def initialize(code:, summary: nil, message: nil, instrumentation_payload: nil)
          @code = code
          @summary = summary
          @message = message
          @instrumentation_payload = instrumentation_payload
        end
      end
    end
  end
end
