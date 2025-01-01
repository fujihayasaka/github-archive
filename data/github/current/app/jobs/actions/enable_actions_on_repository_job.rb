# typed: true
# frozen_string_literal: true

module Actions
  class EnableActionsOnRepositoryJob < ApplicationJob
    include Repositories::Domain::Provider

    class AppInstallationError < StandardError
      attr_reader :reason
      def initialize(message, reason = nil)
        @reason = reason
        super(message)
      end
    end

    queue_as :enable_actions_on_repositories

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    # This job is needed to support a case where required workflows
    # want to run in a repository where actions is not yet enabled.
    # In such situations, we first install the app and then send the
    # input payload to the actions aqueduct queue.
    def perform(payload, target_repo_id, options = {})
      entry_point = options[:entry_point]
      return if payload.nil?

      target_repo = repositories_domain.by_id(target_repo_id)

      return if target_repo.nil?

      with_write do
        result = Actions::AppInstaller.new(target_repo).enable_actions_app(entry_point: entry_point)

        unless result.success?
          GitHub.logger.warn("Failed to install actions app", {
            "gh.catalog_service" => "github/actions",
            "code.namespace" => "Actions::EnableActionsOnRepositoryJob",
            "code.function" => "perform",
            "gh.repo.id" => target_repo.id,
            "gh.integration.name" => "actions",
            "gh.integration.result.error" => result.error,
            "gh.integration.result.reason" => result.reason,
          })

          raise AppInstallationError.new(result.error, result.reason)
        end
      end

      # Verify and add the information about the installation to the payload.
      # This happens when the app is installed on the organization for the
      # first time with this job.
      delivery_payload = payload.dig(:payload)
      installation = delivery_payload&.dig(:installation)
      if installation.nil?
        payload = add_installation_info_to_delivery_payload(payload, target_repo)
      end

      queue = Hook::ActionsDependency.actions_queue_for(payload[:parent])
      job_args = build_aqueduct_job(payload, queue)
      Hook::ActionsDependency.add_ttl_to_aqueduct_job_args(job_args, payload, queue)
      actions_aqueduct_client.send_job(**job_args)

      GitHub.dogstats.increment("repository.enable_actions_app_by_job")
      GitHub.logger.info("Successfully enabled actions app on repo and sent the webhook payload to actions aqueduct queue", {
        "gh.catalog_service" => "github/actions",
        "code.namespace" => "Actions::EnableActionsOnRepositoryJob",
        "code.function" => "perform",
        "gh.repo.id" => target_repo.id,
      })
    end

    private

    def add_installation_info_to_delivery_payload(payload, target_repo)
      event_type = payload.dig(:event)
      return payload unless event_type

      parent = payload.dig(:parent)
      integration_id = parent.sub("integration-", "") if parent.include? "integration-"
      return payload unless integration_id

      scope = IntegrationInstallation.not_suspended.with_target(target_repo.owner).where(integration_id: integration_id)
      filtered_ids = HookEventSubscription.with_name_and_subscriber(event_type, "IntegrationInstallation", scope.ids).pluck(:subscriber_id)
      subscribed_installation = scope.where(id: filtered_ids).select(:id).first
      return payload unless subscribed_installation.present?

      GitHub.logger.info("Extracted the installation information and merged it to the payload", {
        "gh.catalog_service" => "github/actions",
        "code.namespace" => "Actions::EnableActionsOnRepositoryJob",
        "code.function" => "add_installation_info_to_delivery_payload",
        "gh.repo.id" => target_repo.id,
      })

      delivery_payload = payload.dig(:payload)
      delivery_payload = delivery_payload.merge(
        installation: { id: subscribed_installation.id },
      )
      payload[:payload] = delivery_payload
      payload
    end

    def build_aqueduct_job(payload, queue)
      carrier = GitHub.context_propagation_map
      {
        queue: queue,
        payload: payload.to_json(dangerously_allow_all_keys: true),
        headers: carrier,
      }
    end

    def actions_aqueduct_client
      GitHub.build_aqueduct_client(
        app: "actions-#{Rails.env}",
        url: GitHub.aqueduct_gateway_url,
        circuit_breaker: GitHub.aqueduct_gateway_circuit_breaker,
        api_key: GitHub.aqueduct_actions_api_key,
        api_key_version: GitHub.aqueduct_actions_api_key_version,
      )
    end
  end
end
