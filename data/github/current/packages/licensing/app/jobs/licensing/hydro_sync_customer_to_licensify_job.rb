# typed: strict
# frozen_string_literal: true

module Licensing
  # Base class for Hydro jobs that respond to organization events and
  # trigger UpdateCustomerInLicensifyJob for the organization's customer.
  #
  # Subclasses should:
  # 1. Set their queue with `queue_as`
  # 2. Override `should_process?` to implement event-specific logic
  # 3. Override `extract_message_attributes` if they need additional message data
  class HydroSyncCustomerToLicensifyJob < HydroMessageJob
    extend T::Helpers

    abstract!

    include GitHub::Memoizer

    retry_on_dirty_exit

    resolve_tenant_context do |message|
      org_id = message.dig(:organization, :id)
      ::Organization.find_by(id: org_id)&.business
    end

    sig { returns(Integer) }
    attr_reader :organization_id

    sig { params(protobuf: T.untyped, headers: T.untyped, schema: T.untyped, timestamp: T.untyped, timestamp_nano: T.untyped, message: T.untyped, queue: T.untyped).void }
    def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
      super

      organization = message[:organization]
      @organization_id = T.let(organization[:id], Integer)

      extract_message_attributes(message)

      GitHub.context.push(organization_id: @organization_id)
      Failbot.push("gh.org.id": @organization_id)
    end

    sig { void }
    def perform
      return if GitHub.enterprise?
      return unless should_process?

      organization = ::Organization.find_by(id: @organization_id)
      return unless organization&.customer

      UpdateCustomerInLicensifyJob.perform_later(T.must(organization.customer).id)
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_log_context
      super.merge({
        app: "github-licensing"
      })
    end

    protected

    # Override in subclasses to extract additional attributes from the message
    sig { overridable.params(message: T::Hash[Symbol, T.untyped]).void }
    def extract_message_attributes(message)
      # Default implementation does nothing
    end

    # Override in subclasses to implement event-specific filtering logic
    # Return true if the event should trigger a customer update
    sig { overridable.returns(T::Boolean) }
    def should_process?
      true
    end
  end
end
