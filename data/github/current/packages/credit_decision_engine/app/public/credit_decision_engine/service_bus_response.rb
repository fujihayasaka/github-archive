# typed: strict
# frozen_string_literal: true

# Parses the Service Bus response received from Microsoft CDE (Credit Decision Engine) API service.
class CreditDecisionEngine::ServiceBusResponse
  extend T::Sig

  sig { returns(String) }
  attr_reader :request_id
  sig { returns(Symbol) }
  attr_reader :status
  sig { returns(T.nilable(DateTime)) }
  attr_reader :result_date
  sig { returns(T.nilable(String)) }
  attr_reader :reference_id
  sig { returns(T.nilable(Float)) }
  attr_reader :amount
  sig { returns(T.nilable(String)) }
  attr_reader :notes

  sig { params(request_id: String, status: Symbol, result_date: T.nilable(DateTime), reference_id: T.nilable(String), amount: T.nilable(Float), notes: T.nilable(String)).void }
  def initialize(request_id:, status:, result_date:, reference_id: nil, amount: nil, notes: nil)
    @request_id = request_id
    @status = status
    @result_date = result_date
    @reference_id = reference_id
    @amount = amount
    @notes = notes
  end

  sig { params(response: T::Hash[T.any(String, Symbol), T.untyped]).returns(CreditDecisionEngine::ServiceBusResponse) }
  def self.parse(response:)
    errors = self.validate(response)
    if errors.any?
      raise CreditDecisionEngine::ServiceBusResponseError.new("Request number: #{response[:RequestNumber]}, reference number: #{response[:SourceReferenceID]}, errors: #{errors.join(", ")}")
    end

    CreditDecisionEngine::ServiceBusResponse.new(
      request_id: response[:RequestNumber],
      reference_id: response[:SourceReferenceID],
      status: get_status(response: response),
      amount: response[:Amount].to_f,
      result_date: get_final_result_date(response: response),
      notes: response[:Notes],
    )
  end

  sig { params(response: T::Hash[T.any(String, Symbol), T.untyped]).returns(T::Array[String]) }
  private_class_method def self.validate(response)
    errors = []
    errors << "missing RequestNumber" unless response.dig(:RequestNumber).present?
    return errors << "missing Status" unless response.dig(:Status).present?

    status = get_status(response: response)
    return errors << "invalid status #{response.dig(:Status)}" unless Billing::CreditCheck.statuses.include?(status)

    errors
  end

  sig { params(response: T::Hash[T.any(String, Symbol), T.untyped]).returns(Symbol) }
  private_class_method def self.get_status(response:)
    response[:Status].underscore.parameterize(separator: "_").to_sym
  end

  sig { params(response: T::Hash[T.any(String, Symbol), T.untyped]).returns(T.nilable(DateTime)) }
  private_class_method def self.get_final_result_date(response:)
    return nil unless response[:FinalResultDate].present?

    DateTime.parse(response[:FinalResultDate])
  end
end
