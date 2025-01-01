# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ActionsRunnerAdmin
      # The address of the runner-admin service.
      # e.g. "https://actions-runner-admin-production.service.iad.github.net"
      attr_accessor :actions_runner_admin_address

      # The address of the runner-admin service.
      # e.g. "https://actions-runner-admin-lab.service.iad.github.net"
      attr_accessor :actions_runner_admin_address_lab

      # List of space delimited HMAC secrets used to sign requests between dotcom and actions-runner-admin
      attr_accessor :actions_runner_admin_twirp_hmac_keys

      # List of space delimited HMAC secrets used to sign requests between dotcom and actions-runner-admin
      attr_accessor :actions_runner_admin_twirp_hmac_keys_lab

      def runner_admin_client
        @runner_admin_client ||= ::ActionsRunnerAdmin::Twirp::RunnerAdminClient.new(
          actions_runner_admin_address: actions_runner_admin_address,
          actions_runner_admin_twirp_hmac_keys: actions_runner_admin_twirp_hmac_keys
        )
      end

      def runner_admin_client_lab
        @runner_admin_client_lab ||= ::ActionsRunnerAdmin::Twirp::RunnerAdminClient.new(
          actions_runner_admin_address: actions_runner_admin_address_lab,
          actions_runner_admin_twirp_hmac_keys: actions_runner_admin_twirp_hmac_keys_lab
        )
      end

      def build_runner_admin_client(entity)
        return runner_admin_client unless GitHub.flipper[:use_runner_admin_lab].enabled?(entity)
        runner_admin_client_lab
      end
    end
  end

  extend Config::ActionsRunnerAdmin
end
