# typed: strict
# frozen_string_literal: true

module Exemptions
  class ExemptionEvaluator
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { returns(String) }
    attr_reader :request_type

    sig { params(request_type: String).void }
    def initialize(request_type:)
      @request_type = request_type
    end

    sig { abstract.params(request: ExemptionRequest, responses: T::Array[ExemptionResponse]).returns(EvaluationResult) }
    def evaluate(request, responses); end

    sig { overridable.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def request_notification_configuration(request)
      nil
    end

    sig { overridable.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def response_notification_configuration(request)
      nil
    end

    sig { overridable.params(request: ExemptionRequest).returns(T.nilable(Types::ExemptionRequestDataHash)) }
    def exemption_data_hash(request)
      nil
    end

    sig { overridable.params(request: ExemptionRequest).returns(T.nilable(T::Array[Integer])) }
    def notification_user_ids(request)
      nil
    end

    sig { overridable.params(request: ExemptionRequest).returns(T.nilable(String)) }
    def permalink(request)
      nil
    end

    sig { abstract.params(request: ExemptionRequest, reviewer: RuleEngine::Types::Actor).returns(T::Boolean) }
    def is_valid_reviewer?(request, reviewer); end

    sig { abstract.params(request: ExemptionRequest, requester: User).returns(T::Array[T.untyped]) }
    def is_valid_requester?(request, requester); end

    # Result for exemption evaluation
    class EvaluationResult < T::Enum
      enums do
        Approved = new
        Rejected = new
        Pending = new
      end
    end
  end
end
