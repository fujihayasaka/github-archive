# typed: true
# frozen_string_literal: true

# This class exists to add message to
# Aqueduct that will eventually be picked up by the pages deployer service.
#

class GitHub::Pages::PagesDeployerClient
  AQUEDUCT_APP_NAME = "pages-deployer"
  AQUEDUCT_UNACKED_REDELIVERY_TIMEOUT = 20 # seconds

  def self.default_aqueduct_client
    @aqueduct_client ||= GitHub.build_aqueduct_client(
      app: AQUEDUCT_APP_NAME,
      url: GitHub.aqueduct_gateway_url,
      circuit_breaker: GitHub.aqueduct_gateway_circuit_breaker,
      api_key: GitHub.aqueduct_pages_deployer_api_key,
      api_key_version: GitHub.aqueduct_pages_deployer_api_key_version,
    )
  end

  def self.clear_default_aqueduct_client
    # Necessary when tests mock the client and need to refresh it between tests
    @aqueduct_client = nil
  end

  def self.build_aqueduct_job(payload, queue)
    {
      payload: GitHub::JSON.encode(payload),
      queue: queue,
      redelivery_timeout_secs: AQUEDUCT_UNACKED_REDELIVERY_TIMEOUT,
    }
  end

  def self.enqueue(payload, queue)
    job = self.build_aqueduct_job(payload, queue)
    resp = self.default_aqueduct_client.send_job(**job)
    GitHub.logger.info("Job sent to Aqueduct for pages-deployer", {
      "gh.catalog_service" => "github/pages",
      "code.function" => "Pages::PagesDeployerClient#enqueue",
      "code.namespace" => "github/pages/pages_deployer_client",
      "gh.repo.id" => payload[:repo_id],
      "gh.job.id" => resp[:job_id],
      "gh.pages.queue.name" => queue,
      "gh.pages.request.id" => GitHub.context[:request_id],
    })
  end
end
