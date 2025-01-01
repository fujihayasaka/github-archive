# typed: true
# frozen_string_literal: true

module DependencyGraph
  # This class exists to house a number of methods that are used to add jobs to
  # Aqueduct that will eventually be picked up by the Dependency Graph API service.
  #
  # See also:
  # - Hook::DeliverySystem
  class CrossServiceJob
    AQUEDUCT_APP_NAME = "dependency-graph-api"
    AQUEDUCT_UNACKED_REDELIVERY_TIMEOUT = 20 # seconds

    def self.default_aqueduct_client
      @aqueduct_client ||= GitHub.build_aqueduct_client(
        app: AQUEDUCT_APP_NAME,
        url: GitHub.aqueduct_dependency_graph_url,
        send_hmac_secret: GitHub.aqueduct_dependency_graph_send_secret,
        api_key: GitHub.aqueduct_dependency_graph_api_key,
        api_key_version: GitHub.aqueduct_dependency_graph_api_key_version,
      )
    end

    def self.clear_default_aqueduct_client
      # Necessary when tests mock the client and need to refresh it between tests
      @aqueduct_client = nil
    end

    def self.build_aqueduct_job(dg_job_class, dg_job_args, queue)
      {
        headers: GitHub.context_propagation_map,
        payload: {
          arguments: dg_job_args,
          job_class: dg_job_class,
          queue_name: queue,
        }.to_json,
        queue: queue,
        redelivery_timeout_secs: AQUEDUCT_UNACKED_REDELIVERY_TIMEOUT,
      }
    end

    def self.enqueue(job_class:, args:, queue: "service-to-service")
      job = self.build_aqueduct_job(job_class, args, queue)
      resp = self.default_aqueduct_client.send_job(**job)
      GitHub.logger.info("Job sent to Aqueduct for dependency-graph-api", {
        "code.function" => "DependencyGraph::CrossServiceJob#enqueue",
        "gh.job.class" => job_class,
        "gh.job.aqueduct_job_id" => resp[:job_id],
        "gh.job.queue" => queue,
        "gh.request_id" => GitHub.context[:request_id],
      })
    end
  end
end
