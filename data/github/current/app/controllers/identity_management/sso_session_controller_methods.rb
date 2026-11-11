# typed: true
# frozen_string_literal: true

module IdentityManagement::SsoSessionControllerMethods
  private

  def revoke_external_session(target:, actor:, subject:, session_id:)
    external_session = find_external_session(target, session_id)

    if external_session&.user_id == subject.id
      external_session.destroy
      target.instrument_sso_session_revoked(actor: actor, user: subject)
      external_session
    end
  end

  def find_external_session(target, session_id)
    if GitHub.enterprise?
      SAML::Session.find_by(id: session_id)
    else
      return unless provider = find_external_provider(target)
      ExternalIdentitySession.by_sso_provider(provider).find_by(id: session_id)
    end
  end

  def find_external_provider(target)
    session_owner = target.external_identity_session_owner
    return session_owner.external_provider if session_owner.is_a?(Business)

    session_owner.saml_provider
  end
end
