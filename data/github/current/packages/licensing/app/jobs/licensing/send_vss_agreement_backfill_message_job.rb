# typed: strict
# frozen_string_literal: true

class Licensing::SendVssAgreementBackfillMessageJob < ApplicationJob
  include GitHub::Memoizer

  queue_as :licensing
  retry_on_dirty_exit

  retry_on Faraday::Error, GitHub::AzureServiceBus::HttpClient::FailedRequestError, wait: :polynomially_longer, attempts: 20

  locked_by key: -> (job) { job.locking_key }, timeout: 5.minutes

  LOCK_KEY_PREFIX = "licensing/send_vss_agreement_backfill_message_job"
  AZURE_SERVICE_BUS_TOKEN_AUDIENCE = "https://servicebus.azure.net/"
  BACKFILL_QUEUE = "backfill-agreement"

  before_enqueue do
    throw(:abort) unless GitHub.billing_enabled?
  end

  sig { params(enterprise_agreement: Licensing::EnterpriseAgreement).void }
  def perform(enterprise_agreement)
    return unless enterprise_agreement.business.present?
    return unless FeatureFlag.vexi.enabled?(:licensing_vss_agreement_backfill, enterprise_agreement.business, default: false)
    return unless enterprise_agreement.visual_studio_bundle?

    message = Licensing::Vss::AgreementBackfillMessage.new(
      enterprise_agreement_number: enterprise_agreement.agreement_id
    ).serialize_message
    service_bus_client.send_message(message)

    enterprise_agreement.instrument("send_backfill_message")
    GitHub.dogstats.increment("send_vss_agreement_backfill_message_job", tags: ["perform:performed"])
  end

  sig { returns(String) }
  def locking_key
    "#{LOCK_KEY_PREFIX}:#{arguments.first.id}"
  end

  private

  sig { returns(GitHub::AzureServiceBus::QueueClient) }
  memoize def service_bus_client
    azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
    token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
    token_provider_settings.token_audience = AZURE_SERVICE_BUS_TOKEN_AUDIENCE
    token_provider = GitHub::Azure::ApplicationTokenProvider.new(
      GitHub.licensing_azure_spn_tenant_id,
      GitHub.licensing_azure_spn_client_id,
      GitHub.licensing_azure_spn_client_secret,
      token_provider_settings
    )

    GitHub::AzureServiceBus::QueueClient.new(
      queue_name: BACKFILL_QUEUE,
      namespace: GitHub.vss_service_bus_namespace,
      token_provider: token_provider
    )
  end
end
