# typed: true
# frozen_string_literal: true
#
# Helper class for publishing Alive messages related to Security Configurations.
# All published messages must fit into the corresponding front-end `AliveEventData` interface.
#
module SecurityProductsEnablement
  class LiveUpdatePublisher
    extend T::Sig

    sig { returns(Organization) }
    attr_accessor :organization

    sig { params(organization: Organization).void }
    def initialize(organization)
      @organization = organization
    end

    sig { params(repository_id: Integer, status: T.nilable(String), failure_reason: T.nilable(String), config_id: T.nilable(Integer)).void }
    def repository_status(repository_id:, status: nil, failure_reason: nil, config_id: nil)
      # Ensure that the status matches those defined in the TypeScript SecurityConfigurationStatus enum:
      raise ArgumentError, "Unsupported status" unless status.in?(RepositorySecurityConfiguration.states.keys) || status.nil?

      payload = { status:, failure_reason: }
      payload.merge!({ configuration_id: config_id }) if config_id.present?

      publish({
        type: "repository_statuses",
        repositoryStatuses: { repository_id => payload }
      })
    end

    # Notify subscribed users that one or more updated_configurations have changed:
    sig { void }
    def configuration_updates
      publish({ type: "configuration_updates" })
    end

    private

    sig { params(message: T::Hash[T.untyped, T.untyped]).void }
    def publish(message)
      GitHub::WebSocket.notify_security_configurations_update_channel(
        organization,
        GitHub::WebSocket::Channels.security_configurations_update(organization),
        message
      )
    end
  end
end
