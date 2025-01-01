# typed: true
# frozen_string_literal: true

class SamlSessionRevokeJob < ApplicationJob
  queue_as :saml_session_revoke
  schedule interval: 60.seconds

  # Public: Returns true for an Enterprise instances configured with SAML.
  def self.enabled?
    GitHub.enterprise? && GitHub.auth.saml?
  end

  # Public: Revoke UserSessions that are past the expiry specified by the
  # original authentication response.
  #
  # Returns nothing.
  def perform
    return unless self.class.enabled?
    GitHub.instrument "saml_session_revoke.perform" do
      SAML::Session.expired.each_record do |saml_session|
        with_write { saml_session.destroy }
      end
    end
  end
end
