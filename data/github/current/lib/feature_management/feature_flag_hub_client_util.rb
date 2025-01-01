# typed: strict
# frozen_string_literal: true

module FeatureManagement
  class FeatureFlagHubClientUtil
    extend T::Sig
    MAX_ASYNC_GET_OPERATION_ATTEMPTS = 15 # max of 15 1 second sleeps waiting for getoperation to be done

    sig { params(response: Faraday::Response, not_found_allowed: T::Boolean).void }
    def self.process_response_error(response, not_found_allowed)
      return if response.status == 404 && not_found_allowed
      data = JSON.parse(response.body)
      raise FeatureManagement::FeatureFlagHubValidationError.new(data.dig("error", "message")) if response.status == 400
      raise FeatureManagement::FeatureFlagHubPreconditionFailedError.new if response.status == 412
      raise FeatureManagement::FeatureFlagHubAsyncOperationError.new(data["status_code"], data.dig("error", "code"), response.body) if response.status >= 300
    end

    sig { params(client: GitHub::FaradayClient::Internal, endpoint: String, operation_id: String).returns(FeatureManagement::Core::Operation) }
    def self.process_pending_response_completion(client, endpoint, operation_id)
      body = { id: operation_id }.to_json
      url = "#{endpoint}/GetOperation"
      attempts = 1
      loop do
        async_response = client.post(url) do |req|
          req.body = body
        end
        data = JSON.parse(async_response.body)
        if async_response.status < 400 && data["done"] == false
          sleep(1)
          attempts = attempts + 1
          raise FeatureManagement::FeatureFlagHubClientError.new(:async_timeout, "Maximum attempts to obtain completed status has been reached.") if attempts == FeatureManagement::FeatureFlagHubClientUtil::MAX_ASYNC_GET_OPERATION_ATTEMPTS
        else
          return FeatureManagement::Core::Operation.new(data["id"], data["done"], data["status_code"]) if async_response.status < 300
          FeatureManagement::FeatureFlagHubClientUtil.process_response_error(async_response, false)
        end
      end
    end
  end
end
