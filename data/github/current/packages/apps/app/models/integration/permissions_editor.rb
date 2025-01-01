# typed: true
# frozen_string_literal: true
class Integration
  class PermissionsEditor
    attr_reader :integration, :new_permissions_and_events

    # Result from the IntegrationPermissionsEditor
    class Result
      class Error < StandardError; end

      def self.success(integration) new(:success, integration: integration) end
      def self.failed(error, integration) new(:failed, error: error, integration: integration) end

      attr_reader :error, :integration

      def initialize(status, integration: nil, error: nil)
        @status      = status
        @integration = integration
        @error       = error
      end

      def success?
        @status == :success
      end

      def failed?
        @status == :failed
      end
    end

    def self.perform(integration:, permissions_and_events:)
      new(integration: integration, permissions_and_events: permissions_and_events).perform
    end

    def initialize(integration:, permissions_and_events:)
      @integration                = integration
      @new_permissions_and_events = permissions_and_events
    end

    def perform
      old_version = integration.latest_version

      if integration.update(new_permissions_and_events)
        integration.touch

        unless Apps::Internal.capable?(:skip_version_update, app: integration)
          version = integration.reload.latest_version
          UpgradeIntegrationInstallationVersionJob.perform_later(integration.id, nil, version.number)
        end
      else
        # this hack is temporary as we switch the underlying structure of single file permissions and want to avoid duplicated messages
        # https://github.com/github/ecosystem-apps/issues/335#issuecomment-671661660
        message = integration.errors.full_messages.reject { |message| message.include? "Single files path" }.join("\n")
        raise Result::Error, message
      end

      Result.success(integration)
    rescue Result::Error => e
      Result.failed e.message, integration
    end
  end
end
