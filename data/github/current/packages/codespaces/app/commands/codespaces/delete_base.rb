# typed: true
# frozen_string_literal: true

module Codespaces
  class DeleteBase < Command
    attr_reader :codespace, :reason

    class UnimplementedError < StandardError; end

    def initialize(codespace, reason: Codespace.deletion_reasons[:user_requested], error_reporter: Codespaces::ErrorReporter, skip_vscs: false)
      @codespace = codespace
      @error_reporter = error_reporter
      @reason = reason
      @skip_vscs = skip_vscs
    end

    def perform
      return if codespace.deleted?

      @error_reporter.push(codespace: codespace)

      return unless codespace.deprovisioning?

      if codespace.guid && !@skip_vscs
        delete_environment_from_service
      end

      instrument_deletion!

      Codespaces::BillingEntry.
        where(codespace_guid: codespace.guid, codespace_deprovisioned_at: nil).
        touch_all(:codespace_deprovisioned_at)

      Codespaces::MaximumIdleTimeoutPolicy.delete_has_override_key!(codespace.id)
      delete_codespace
    end

    private

    def delete_environment_from_service
      raise UnimplementedError, "delete_environment_from_service must be implemented in a subclass"
    end

    def delete_codespace
      raise UnimplementedError, "delete_codespace must be implemented in a subclass"
    end

    def client
      # We use unscoped deletion because the codespaces.owner might be deleted.
      @client ||= Codespaces::VscsClient.for_unscoped_deletion_or_suspension(
        codespace.plan,
        codespace.vscs_target,
        api_url: Codespaces::VscsApiUrl.for_codespace(codespace),
        user: codespace.owner,
      )
    end

    def instrument_deletion!
      actor = codespace.owner if reason == Codespace.deletion_reasons[:user_requested]
      codespace.instrument(:suspend_environment, actor:) if codespace.consuming_compute?
      codespace.instrument(:deprovision_environment, actor:)
    end
  end
end
