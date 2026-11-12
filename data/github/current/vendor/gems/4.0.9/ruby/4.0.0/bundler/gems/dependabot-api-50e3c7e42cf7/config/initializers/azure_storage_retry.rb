# frozen_string_literal: true
# typed: ignore

require "active_storage/service/azure_storage_service"
require "azure/storage/common"

class DependabotAzureRetryFilter < Azure::Storage::Common::Core::Filter::ExponentialRetryPolicyFilter
  def initialize
    super(5, 20, 120) # Retry up to 5 times, with min 20s and max 120s intervals
  end

  def should_retry_on_error?(response, retry_data)
    Dependabot::Logger.info(
      msg: "Azure Storage error retry attempt",
      count: retry_data[:count],
      error: retry_data[:error].inspect,
      retryable: retry_data[:retryable],
      location: retry_data[:current_location],
      status_code: retry_data[:status_code]
    )
    decision = super
    Dependabot::Logger.info(
      msg: "Azure Storage error retry decision",
      count: retry_data[:count],
      retryable: retry_data[:retryable]
    )
    decision
  end

  def should_retry_on_local_error?(retry_data)
    Dependabot::Logger.info(
      msg: "Azure Storage local error retry attempt",
      count: retry_data[:count],
      error: retry_data[:error].inspect,
      retryable: retry_data[:retryable],
    )
    decision = super
    Dependabot::Logger.info(
      msg: "Azure Storage local error retry decision",
      count: retry_data[:count],
      retryable: retry_data[:retryable]
    )
    decision
  end
end

module AzureStorageRetryPatch
  def initialize(storage_account_name:, storage_access_key:, container:, public: false, **options)
    super
    return unless Dependabot::Application.monolith_feature_enabled?(feature: :dependabot_abs_retries)

    @client.with_filter(DependabotAzureRetryFilter.new)
  end
end

ActiveStorage::Service::AzureStorageService.prepend(AzureStorageRetryPatch)
