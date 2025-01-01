# typed: strict
# frozen_string_literal: true

require "zuorest"

if GitHub.billing_enabled?
  background_job = GitHub.role.to_s.include?("worker")
  GitHub.zuorest_client = Zuorest::RestClient.new(
    server_url: GitHub.zuora_rest_server,
    access_key_id: GitHub.zuora_access_key_id,
    secret_access_key: GitHub.zuora_secret_access_key,
    client_id: GitHub.zuora_client_id,
    client_secret: GitHub.zuora_client_secret,
    apm_server_url: GitHub.zuora_apm_rest_server,
    apm_username: GitHub.zuora_apm_username,
    apm_api_token: GitHub.zuora_apm_api_token,
    timeout: (background_job ? 60 : 5),
    open_timeout: (background_job ? 60 : 5),
    logger: GitHub::Telemetry::Logs.lib_logger("Zuorest"),
    token_storage: GitHub::Billing::ZuorestTokenStorage.new,
    adapter: :typhoeus,
  ) do |conn|
    conn.use GitHub::FaradayMiddleware::TracingUrlTemplate
    conn.request :instrumentation, name: "billing.zuora_client.request", instrumenter: GlobalInstrumenter
  end
  Zuorest::Model::Base.zuora_rest_client = GitHub.zuorest_client

  GitHub.zuorest_background_worker_client = Zuorest::RestClient.new(
    name: "Zuorest Background Worker Client",
    server_url: GitHub.zuora_rest_server,
    access_key_id: GitHub.zuora_access_key_id,
    secret_access_key: GitHub.zuora_secret_access_key,
    client_id: GitHub.zuora_client_id,
    client_secret: GitHub.zuora_client_secret,
    apm_server_url: GitHub.zuora_apm_rest_server,
    apm_username: GitHub.zuora_apm_username,
    apm_api_token: GitHub.zuora_apm_api_token,
    timeout: 120,
    open_timeout: 120,
    logger: GitHub::Telemetry::Logs.lib_logger("Zuorest::BackgroundWorker"),
    token_storage: GitHub::Billing::ZuorestTokenStorage.new,
    adapter: :typhoeus,
  ) do |conn|
    conn.use GitHub::FaradayMiddleware::TracingUrlTemplate
    conn.request :instrumentation, name: "billing.zuora_client.retry_client.request", instrumenter: GlobalInstrumenter
    conn.request :retry, {
      retry_statuses: [429],
      exceptions: [Faraday::RetriableResponse],
      retry_block: -> (env, options, retry_count, exception) {
        GitHub.logger.info(
          "Retrying Zuora request",
          "code.namespace" => "Zuorest::RestClient",
          "code.function" => "zuora_client.retry",
          "gh.billing.zuorest.retry.count" => retry_count,
          "gh.exception" =>  exception,
          "gh.billing.zuorest.retry.options" => options,
          "gh.billing.zuorest.env" => env,
        )
        GitHub.dogstats.increment("billing.zuora_client.retry", tags: [
          "retry_count:#{retry_count}"
        ])
      }
    }
  end
end
