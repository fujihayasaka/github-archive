# typed: true
# frozen_string_literal: true

module ActionsRunnerAdmin
  module Twirp
    class BaseClient
      TWIRP_PATH = "/twirp"
      FAILBOT_APP_NAME = "github-actions-runner-admin"
      SERVICE_NAME = "github-actions-runner-admin"
      CONNECTION_OPEN_TIMEOUT = 1 # in seconds
      READ_TIMEOUT = 10 # in seconds

      def initialize(actions_runner_admin_address: GitHub.actions_runner_admin_address, actions_runner_admin_twirp_hmac_keys: GitHub.actions_runner_admin_twirp_hmac_keys)
        @actions_runner_admin_address = actions_runner_admin_address
        @actions_runner_admin_twirp_hmac_keys = actions_runner_admin_twirp_hmac_keys
      end

      # This method wraps the TwirpClient#rpc method with handling the errors
      # from a actions-runner-admin response
      def rpc(method, params)
        TwirpHelper.rescue_from_twirp_errors(FAILBOT_APP_NAME, app: FAILBOT_APP_NAME) do
          client.rpc(method, params)
        end
      end

      private

      def hmac_key
        @hmac_key ||= @actions_runner_admin_twirp_hmac_keys.split(" ").last
      end

      def actions_runner_admin_configured?
        @actions_runner_admin_address.present? && @actions_runner_admin_twirp_hmac_keys.present?
      end

      # This method is used in the case where the API returns a 404 and properly formed
      # blank protocol buffer ;)
      def empty_message(method)
        output_class = twirp_class.rpcs[method.to_s][:output_class]

        output_class.new
      end

      def twirp_class
        raise "Must define 'twirp_class' to return a Twirp::Client class that describes the remote service."
      end

      def client
        @client ||= build_client
      end

      def build_client
        unless actions_runner_admin_configured?
          failbot_report(ActionsRunnerAdmin::Twirp::Error.new("Actions Runner Admin HMAC and URL not set."))

          return ActionsRunnerAdmin::Twirp::NullClient.new
        end

        twirp_class.new(connection)
      end

      def connection_url
        URI.join(@actions_runner_admin_address, TWIRP_PATH).to_s
      end

      def connection
        @connection ||= GitHub::FaradayClient::Internal.new(connection_url) do |conn|
          conn.use GitHub::FaradayMiddleware::Retries,
            client_name: SERVICE_NAME, retry_statuses: [500, 503], methods: [:post]
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_key
          conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
          conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
            instrumenter: GitHub,
            sleep_window_seconds: 10,
            request_volume_threshold: 20,
            error_threshold_percentage: 5,
            window_size_in_seconds: 30,
            bucket_size_in_seconds: 5,
          }
          conn.options[:open_timeout] = CONNECTION_OPEN_TIMEOUT
          conn.options[:timeout] = READ_TIMEOUT
          conn.adapter :persistent_excon
        end
      end

      def failbot_report(error)
        Failbot.report(error, { app: FAILBOT_APP_NAME })
      end

      def build_runner_admin_entity(owner)
        case owner
        when Repository
          build_entity(owner.next_global_id, owner.next_global_id, owner.owner&.next_global_id, owner.business&.next_global_id)
        when Organization
          build_entity(owner.next_global_id, nil, owner.next_global_id, owner.business&.next_global_id)
        when Business
          build_entity(owner.next_global_id, nil, nil, owner.next_global_id)
        end
      end

      def build_entity(entity_id, repo_id, org_id, enterprise_id)
        hierarchy = GitHub::ActionsRunnerAdmin::Entities::V1::GitHubEntityHierarchy.new(
          repository_id: build_identity(repo_id),
          organization_id: build_identity(org_id),
          enterprise_id: build_identity(enterprise_id)
        )

        GitHub::ActionsRunnerAdmin::Entities::V1::GitHubEntity.new(entity_id: build_identity(entity_id), hierarchy: hierarchy)
      end

      def build_identity(entity_id)
        return nil unless entity_id.present?
        GitHub::ActionsRunnerAdmin::Entities::V1::Identity.new(global_id: entity_id)
      end
    end
  end
end
