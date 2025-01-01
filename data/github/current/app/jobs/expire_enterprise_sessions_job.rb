# typed: true
# frozen_string_literal: true

class ExpireEnterpriseSessionsJob < ApplicationJob
  queue_as :expire_enterprise_sessions

  def perform(enterprise)
    return unless enterprise.saml_sso_enabled? && enterprise.saml_provider.saml_deprovisioning_enabled?

    with_write do
      enterprise.saml_provider.external_identity_sessions.active.update_all(expires_at: 1.minute.ago)
    end
  end
end
