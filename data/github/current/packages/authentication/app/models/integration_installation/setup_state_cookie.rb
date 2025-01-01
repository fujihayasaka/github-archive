# typed: true
# frozen_string_literal: true

# This models the `setup_url` param that we allow integrators to pass when linking
# to an apps installation or marketplace listing page.
#
# It's stored in a cookie in the users session.
#
# It is used to determine the state param we might pass back to integrators
# when we redirect back to their `setup_url`
class IntegrationInstallation::SetupStateCookie
  COOKIE_NAME = :integration_setup_state

  def self.create(cookie_jar:, data:, integration_id:, target_id: nil)
    new(cookie_jar: cookie_jar, data: data, integration_id: integration_id, target_id: target_id).save
  end

  def self.delete(cookie_jar:)
    cookie_jar.delete(COOKIE_NAME)
  end

  attr_reader :cookie_jar, :integration_id, :data, :target_id
  private :cookie_jar

  def initialize(cookie_jar:, data: nil, integration_id: nil, target_id: nil)
    @data = data
    @cookie_jar = cookie_jar
    @integration_id = integration_id
    @target_id = target_id
    load_from_cookie
  end

  def save
    return unless data.present?
    cookie_jar.signed[COOKIE_NAME] = { value: cookie_payload, expires: 1.hour }
    self
  end

  def state_param(integration_id:, target_id: nil)
    return nil unless integration_id.to_s == self.integration_id.to_s
    return nil if self.target_id && target_id.to_i != self.target_id.to_i
    data&.dig("state")
  end

  private

  def cookie_payload
    JSON.generate({
      data: data,
      integration_id: integration_id,
      target_id: target_id,
    })
  end

  def load_from_cookie
    payload = cookie_jar.signed[COOKIE_NAME]
    return unless payload
    payload = JSON.parse(payload)

    @data           ||= payload["data"]
    @integration_id ||= payload["integration_id"]
    @target_id      ||= payload["target_id"]
  end
end
