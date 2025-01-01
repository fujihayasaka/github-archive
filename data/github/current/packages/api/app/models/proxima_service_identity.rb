# typed: true
# frozen_string_literal: true

# Represents a first-party service in a Proxima stamp.
#
# Used to facilitate increased rate limits for unauthenticated requests for registered first-party services
# running in a Proxima stamp.
class ProximaServiceIdentity < ApplicationRecord::Domain::Integrations
  include Instrumentation::Model

  after_commit :instrument_creation, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_destroy, on: :destroy

  REGISTERED_SERVICES = %w[
    actions
    advisory-database
    dependabot
    proxima-api-testing
  ].freeze

  validates :service_name, inclusion: { in: REGISTERED_SERVICES }

  # default unauthenticated rate limit, per hour
  DEFAULT_RATE_LIMITS = {
    "actions" => 5000,
    "advisory-database" => 5000,
    "dependabot" => 5000,
    "proxima-api-testing" => 1000,
  }.freeze

  sig { params(service: String).returns(Integer) }
  def self.default_rate_limit(service)
    raise "unregistered service '#{service}'" unless DEFAULT_RATE_LIMITS.include?(service)
    DEFAULT_RATE_LIMITS[service]
  end

  def event_prefix
    "proxima_service_rate_limit"
  end

  def instrument_creation
    instrument :create
  end

  def instrument_update
    instrument :update
  end

  def instrument_destroy
    instrument :destroy
  end

  def event_payload
    {
      registration_id: id,
      tenant: tenant_shortcode,
      service: service_name,
      rate_limit: rate_limit,
    }
  end
end
