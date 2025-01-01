# typed: true
# frozen_string_literal: true

module Codespaces
  class SuspendEnvironment < Command
    attr_reader :codespace

    def initialize(codespace, user: nil, skip_async_operation_check: false, error_reporter: Codespaces::ErrorReporter, ignore_deleted: false)
      @codespace = codespace
      @error_reporter = error_reporter
      @skip_async_operation_check = skip_async_operation_check
      @user = user
      @ignore_deleted = ignore_deleted
    end

    def perform
      @error_reporter.push(codespace: codespace)

      if codespace.guid
        codespace.ensure_no_blocking_pending_async_operation! unless @skip_async_operation_check
        begin
          env_json = client.shutdown_environment(
            codespace.guid,
            repository: codespace.repository,
            billable_owner: codespace.billable_owner
          )
        rescue Codespaces::VscsClient::BadResponseError => e
          raise e unless @ignore_deleted && e.status == 404
        end

        # The service can shutdown a starting codespace directly so we are unlikely to actually hear back from them
        # in this case. We should mark the operation as ended so we don't end up counting it against our start SLOs.
        codespace.pending_async_operations.start_codespace.each { |op| op.mark_as_ended }

        env = Codespaces::Environment.from_json(env_json)
        ActiveRecord::Base.connected_to(role: :writing) do
          codespace.update!(environment_data: env) if env.present?
        end
      end

      if @user
        Codespaces::PerUserStartTracker.new(@user).codespace_stopped(codespace)
      end

      Codespaces::Events.suspend(codespace)

      if GitHub.flipper[:codespaces_improved_shutdown_auditing].enabled?(codespace.owner)
        Codespaces::InstrumentSuspend.call(codespace:, actor: @user)
      else
        codespace.instrument(:suspend_environment, actor: @user)
      end
    end

    private

    def client
      @client ||= Codespaces::VscsClient.for_unscoped_deletion_or_suspension(
        codespace.plan,
        codespace.vscs_target,
        api_url: VscsApiUrl.for_codespace(codespace),
      )
    end
  end
end
