# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable::Processor
  class ProcessedResult

    UpdatedMemexIDs = T.type_alias { T::Array[Integer] }

    sig { returns(UpdatedMemexIDs) }
    attr_reader :updated_memex_ids

    sig { returns(T::Array[Base::ObjectWithGlobalRelayId]) }
    attr_reader :updated_models

    sig { returns(T.nilable(String)) }
    attr_reader :topic

    sig do
      params(
        failure_reason: T.nilable(String),
        elasticsearch_update_response: T.nilable(ElasticsearchUpdateResponse),
        updated_memex_ids: UpdatedMemexIDs,
        updated_models: T.nilable(T::Array[Base::ObjectWithGlobalRelayId]),
        topic: T.nilable(String),
        broadcast_result: T::Boolean,
      ).void
    end
    def initialize(
      failure_reason: nil,
      elasticsearch_update_response: nil,
      updated_memex_ids: [],
      updated_models: nil,
      topic: nil,
      broadcast_result: true
    )
      @topic = topic
      @failure_reason = failure_reason
      @elasticsearch_update_response = elasticsearch_update_response
      @updated_memex_ids = updated_memex_ids
      @updated_models = T.let(updated_models || [], T::Array[Base::ObjectWithGlobalRelayId])
      @broadcast_result = broadcast_result

      validate_input!
    end

    sig { returns(Base::GenericHash) }
    def outcome
      return { failure_reason: @failure_reason } if @failure_reason

      T.must(@elasticsearch_update_response).data
    end

    sig { returns(T::Boolean) }
    def no_matching_docs?
      outcome[:failure_reason] == FailureReason::NO_MATCHING_DOCS
    end

    sig { returns(T::Boolean) }
    def content_missing?
      outcome[:failure_reason] == FailureReason::CONTENT_MISSING
    end

    sig { returns(T::Boolean) }
    def message_ignored?
      outcome[:failure_reason] == FailureReason::MESSAGE_IGNORED
    end

    sig { returns(T::Boolean) }
    def project_missing?
      outcome[:failure_reason] == FailureReason::PROJECT_MISSING
    end

    sig { returns(T::Boolean) }
    def partial_resync?
      outcome[:failure_reason] == FailureReason::PARTIAL_RESYNC
    end

    sig { returns(T::Boolean) }
    def failure_reason?
      outcome[:failure_reason].present?
    end
    alias_method :failed?, :failure_reason?

    sig { returns(T::Boolean) }
    def version_conflicts?
      conflict_count.positive?
    end

    sig { returns(Integer) }
    def conflict_count
      outcome[:version_conflicts].to_i
    end

    sig { returns(T::Boolean) }
    def failures_or_errors_to_report?
      outcome[:failures].present? || outcome[:errors].present?
    end

    sig { returns(T::Boolean) }
    def broadcast_result? = @broadcast_result

    sig { returns(T.nilable(T.noreturn)) }
    private def validate_input!
      if not_enough_inputs?
        raise ArgumentError.new("Must provide either failure_reason or elasticsearch_update_response")
      end

      if too_many_inputs?
        raise ArgumentError.new("Must provide either failure_reason or elasticsearch_update_response but not both")
      end

      if FailureReason.invalid?(@failure_reason)
        raise ArgumentError.new("Invalid failure_reason")
      end
    end

    sig { returns(T::Boolean) }
    private def not_enough_inputs?
      @failure_reason.nil? && @elasticsearch_update_response.nil?
    end

    sig { returns(T::Boolean) }
    private def too_many_inputs?
      @failure_reason.present? && @elasticsearch_update_response.present?
    end
  end
end
