# typed: true
# frozen_string_literal: true

module Codespaces

  # Export calls into the VSCS service to trigger a branch export of a
  # suspended codespace.  This is to allow users to get their changes from a
  # codespace they can no longer access.
  class Export < Command
    class EnvNotSuspendedError < StandardError; end
    class EnvStillSuspendingError < StandardError; end
    class EnvAlreadyExportingError < StandardError; end

    attr_reader :codespace, :github_token, :new_repository_origin, :actor

    def initialize(codespace, github_token, new_repository_origin: nil, error_reporter: Codespaces::ErrorReporter, actor: nil)
      @codespace = codespace
      @github_token = github_token
      @new_repository_origin = new_repository_origin
      @error_reporter = error_reporter
      @actor = actor
    end

    def perform
      @error_reporter.push(codespace: codespace)

      return unless codespace.exporting?

      # TODO remove the below line once https://github.com/microsoft/vssaas-planning/issues/871 is fixed
      # This will save us a fetch_environment call unless the export fails because it's in the wrong state
      validate_environment_state(codespace.guid)

      codespace.delete_export_branch
      begin
        client.export_environment(codespace.guid,
          branch_name: codespace.export_branch_name,
          repository_name: codespace.repository.name,
          token: github_token,
          new_repository_origin: new_repository_origin,
          failover_details: Codespaces::GetFailoverDetails.call(user: actor || codespace.owner, region: codespace.location, vscs_target: codespace.vscs_target)
        )
      rescue Codespaces::VscsClient::InvalidExportStateError
        validate_environment_state(codespace.guid)
      end
      GitHub.instrument("codespaces.export_environment",
        owner_id: codespace.owner_id,
        owner: codespace.owner.display_login,
        codespace_id: codespace.id,
        plan_id: codespace.plan_id,
        environment_id: codespace.guid,
        repo: codespace.repository,
        actor_id: @actor&.id
      )
    end

    private

    def client
      @client ||= Codespaces::VscsClient.for_codespace(codespace)
    end

    def validate_environment_state(environment_id)
      env = client.fetch_environment!(codespace.guid)
      raise EnvAlreadyExportingError if env["state"] == Vscs::State::EXPORTING
      raise EnvStillSuspendingError if env["state"] == Vscs::State::SHUTTING_DOWN
      raise EnvNotSuspendedError unless env["state"] == Vscs::State::SHUTDOWN
    end
  end
end
