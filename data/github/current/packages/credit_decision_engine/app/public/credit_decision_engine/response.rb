# typed: strict
# frozen_string_literal: true

# Parses the HTTP response received from Microsoft CDE (Credit Decision Engine) API service.
class CreditDecisionEngine::Response
  extend T::Sig

  VALID_ERROR_CODES = T.let(%w(01 02).freeze, T::Array[String])

  sig { returns(String) }
  attr_reader :request_id
  sig { returns(Symbol) }
  attr_reader :status
  sig { returns(T::Hash[T.any(String, Symbol), String]) }
  attr_reader :error

  sig { params(request_id: String, error: T::Hash[T.any(String, Symbol), String]).void }
  def initialize(request_id:, error: {})
    @request_id = request_id
    @status = T.let(:pending_review, Symbol)
    @error = error
  end

  sig { params(response: T::Hash[T.any(String, Symbol), T.untyped]).returns(CreditDecisionEngine::Response) }
  def self.parse(response:)
    errors = self.validate(response)
    if errors.any?
      raise CreditDecisionEngine::ResponseError.new("Request number: #{response[:spocRequestId]}, errors: #{errors.join(", ")}")
    end

    error = response[:Error].presence || {}
    CreditDecisionEngine::Response.new(
      request_id: response[:spocRequestId],
      error: error.compact_blank.transform_keys(&:downcase),
    )
  end

  sig { params(response: T::Hash[T.any(String, Symbol), T.untyped]).returns(T::Array[String]) }
  private_class_method def self.validate(response)
    errors = []
    errors << "missing Request Id" unless response.dig(:spocRequestId).present?
    return errors unless response.dig(:Error).present?
    errors << "missing Error Code" unless response.dig(:Error, :Code).present?
    errors << "missing Error Message" unless response.dig(:Error, :Message).present?

    error_code = response.dig(:Error, :Code)
    errors << "invalid error code #{error_code}" if error_code.present? && VALID_ERROR_CODES.exclude?(error_code)

    errors
  end
end
