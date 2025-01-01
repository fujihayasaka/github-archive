# typed: true
# frozen_string_literal: true

module GitHub::Billing
  # A generic response object that wraps responses from a specific payment
  # processor so that the main GitHub application doesn't need to know their
  # implementation details.
  class PaymentProcessorResponse < PaymentProcessorAdapter

    def self.success(attributes)
      new(true, attributes)
    end

    def self.failure(error, attributes = nil)
      attributes ||= {}
      new(false, attributes.merge(error: error))
    end

    # Public: A PaymentProcessorRecord which generally represents a customer
    # plus payment (credit card) and address information. Can be nil for failed
    # responses.
    attr_reader :record

    # Public: A PaymentProcessorTransaction which represents some kind of payment
    # transaction, such as a charge or a refund. Can be nil for failed responses.
    attr_reader :transaction

    # Public: An ErrorMessage with details about the failure.
    attr_reader :error

    # Public: Boolean if the response succeeded.
    def success?
      !!@success
    end

    # Public: Boolean if the response failed.
    def failed?
      !success?
    end

    # Public: Returns the error message.
    #
    # Returns a string
    def message
      error.to_s
    end

    def error_message
      error
    end

    private

    def initialize(success, attributes = nil)
      @success = success
      super attributes
    end
  end
end
