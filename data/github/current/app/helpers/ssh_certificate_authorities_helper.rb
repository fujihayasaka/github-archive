# typed: true
# frozen_string_literal: true

module SshCertificateAuthoritiesHelper
  def resolve_ssh_ca_path(ssh_ca)
    case ssh_ca.owner
    when Organization
      T.unsafe(self).ssh_certificate_authority_organization_path(ssh_ca.owner.display_login, ssh_ca.id)
    when Business
      T.unsafe(self).ssh_certificate_authority_enterprise_path(ssh_ca.owner.slug, ssh_ca.id)
    end
  end

  def resolve_ssh_ca_require_expiration_path(ssh_ca)
    case ssh_ca.owner
    when Organization
      T.unsafe(self).ssh_certificate_authorities_require_expiration_organization_path(ssh_ca.owner.display_login, ssh_ca.id)
    when Business
      T.unsafe(self).ssh_certificate_authorities_require_expiration_enterprise_path(ssh_ca.owner.slug, ssh_ca.id)
    end
  end
end
