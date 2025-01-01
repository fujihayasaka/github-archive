# typed: strict
# frozen_string_literal: true

class OrganizationHydroMessageJob < HydroMessageJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  extend T::Sig
  include GitHub::Memoizer

  sig { returns(Integer) }
  attr_reader :organization_id

  class OrganizationNotFoundError < StandardError; end

  resolve_tenant_context do |message|
    org_id = message.dig(:organization, :id)
    ::Organization.find_by(id: org_id)&.business
  end

  sig { params(protobuf: T.untyped, headers: T.untyped, schema: T.untyped, timestamp: T.untyped, timestamp_nano: T.untyped, message: T.untyped, queue: T.untyped).void }
  def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
    super

    organization, request_id = message.values_at(
      :organization,
      :request_id
    )
    @organization_id = T.let(organization[:id], Integer)

    GitHub.context.push(organization_id:, request_id:)
    Failbot.push(
      "gh.org.id": organization_id,
      "gh.request_id": request_id,
    )

  end

  sig { returns(Organization) }
  memoize def organization
    org = T.let(::Organization.find(@organization_id), T.nilable(::Organization))
    if org.nil?
      raise OrganizationNotFoundError, "Organization with ID #{@organization_id} not found"
    else
      T.let(org, Organization)
    end
  end

  protected

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def original_message_envelope
    original_event_time = Time.at(timestamp_nano)
    original_event_timestamp = Google::Protobuf::Timestamp.new(seconds: original_event_time.to_i, nanos: original_event_time.nsec)
    Hydro::Schemas::Hydro::V1::Envelope.new(timestamp: original_event_timestamp).to_h
  end

  sig { override.returns(T.untyped) }
  def logging_context
    super.merge({
      "gh.org.id": organization_id,
      "gh.org.login": organization.display_login,
    })
  end

  sig { override.returns(T.untyped) }
  def failbot_log_context
    super.merge({
      "gh.org.id": organization_id
    })
  end
end
