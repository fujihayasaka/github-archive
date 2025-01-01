# typed: true
# frozen_string_literal: true

module Codespaces
  class Restore < Command
    attr_reader :codespace

    class InvalidEnv < Error; end

    def initialize(codespace, error_reporter: Codespaces::ErrorReporter)
      @codespace = codespace
      @error_reporter = error_reporter
    end

    def perform
      @error_reporter.push(codespace: codespace)

      return unless codespace.restorable?
      return unless codespace.accessible?

      env = client.restore_environment(codespace.guid) if codespace.guid
      raise InvalidEnv, "Environment #{codespace.guid} does not exist" unless env

      ActiveRecord::Base.connected_to(role: :writing) do
        Codespace.transaction do
          Codespace.throttle_with_retry do
            codespace.update!(
              deleted_at: nil,
              shutdown_at: nil,
              restored_at: Time.current,
              restore_count: codespace.restore_count + 1,
              environment_data: env,
              state: :provisioned
            )
          end

          Codespaces::BillingEntry.throttle_with_retry do
            Codespaces::BillingEntry.create!(
              codespace: codespace,
              billable_owner: codespace.billable_owner,
              codespace_owner: codespace.owner,
              codespace_guid: codespace.guid,
              codespace_plan_name: codespace.plan.name,
              repository: codespace.repository,
              copilot_workspace_id: codespace.copilot_workspace_id,
              spark_workbench_id: codespace.spark_workbench_id,
            )
          end
        end

        Codespaces::MaximumIdleTimeoutPolicy.set_has_override_key!(codespace.id)
      end

      codespace.reload.notify_socket_subscribers

      # Hydro
      GlobalInstrumenter.instrument("codespaces.restored", codespace: codespace)

      # Audit log
      GitHub.instrument("codespaces.restore",
        owner_id: codespace.owner_id,
        owner: codespace.owner&.display_login,
        codespace_id: codespace.id,
        repo: codespace.repository,
        plan_id: codespace.plan_id,
        environment_id: codespace.guid
      )
    end

    private

    def client
      @client ||= Codespaces::VscsClient.for_codespace(codespace)
    end
  end
end
