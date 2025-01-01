# typed: true
# frozen_string_literal: true

module Codespaces

  # ResizeStorage calls into the VSCS service to trigger a SKU change that
  # includes storage size change, which means the operation is no longer
  # just a DB change on the GH side, as the old storage needs to be copied
  # to a new one of the desired size, which takes longer and can fail.
  class ResizeStorage < Command
    class EnvAlreadyUpdatingError < StandardError; end
    class EnvStillSuspendingError < StandardError; end
    class EnvNotSuspendedError < StandardError; end

    attr_reader :codespace, :new_sku_name, :operation

    def initialize(codespace, new_sku_name, operation: nil, error_reporter: Codespaces::ErrorReporter)
      @codespace = codespace
      @new_sku_name = new_sku_name
      @error_reporter = error_reporter

      operation ||= Codespaces::AsyncOperation.find_by(
          codespace: codespace,
          operation: :update_storage,
          op_ended_at: nil,
        )

      @operation = operation

      @error_reporter.push(codespace: codespace) if codespace
    end

    def perform
      begin
        client.update_environment(codespace.guid, body: { skuName: new_sku_name })
        operation.mark_as_started if operation
      rescue Codespaces::VscsClient::InvalidUpdatingStateError
        validate_environment_state(codespace.guid)
      end

      GitHub.instrument("codespaces.switch_sku_storage",
        owner_id: codespace.owner_id,
        owner: codespace.owner.display_login,
        codespace_id: codespace.id,
        plan_id: codespace.plan_id,
        environment_id: codespace.guid
      )
    end

    private

    def client
      @client ||= Codespaces::VscsClient.for_codespace(codespace)
    end

    def validate_environment_state(environment_id)
      env = client.fetch_environment!(environment_id)
      raise EnvAlreadyUpdatingError if env["state"] == Vscs::State::UPDATING || env["state"] == Vscs::State::QUEUED
      raise EnvStillSuspendingError if env["state"] == Vscs::State::SHUTTING_DOWN
      raise EnvNotSuspendedError unless env["state"] == Vscs::State::SHUTDOWN
    end
  end
end
