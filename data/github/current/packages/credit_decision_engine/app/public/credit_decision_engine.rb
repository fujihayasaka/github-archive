# typed: strict
# frozen_string_literal: true

module CreditDecisionEngine
  class AuthenticationError < StandardError; end
  class RequestError < StandardError; end
  class ResponseError < StandardError; end
  class ServiceBusResponseError < StandardError; end
end
