# typed: true
# frozen_string_literal: true

class RateLimitKey
  def self.for(obj)
    case obj
    when Bot
      case obj.installation
      when ScopedIntegrationInstallation
        if obj.installation.per_repo_rate_limit?
          "installation-#{obj.installation.integration_installation_id}-#{obj.installation.repository_ids.first}"
        else
          "installation-#{obj.installation.integration_installation_id}"
        end
      when SiteScopedIntegrationInstallation
        if obj.installation.per_repo_rate_limit?
          "site-installation-#{obj.installation.integration_id}-#{obj.installation.target_id}-#{obj.installation.repository_ids.first}"
        elsif obj.installation.repo_owner_rate_limit?
          "site-installation-#{obj.installation.integration_id}-#{obj.installation.target_id}"
        else
          "site-installation-#{obj.installation.id}"
        end
      when nil
        self.for(obj.integration)
      else
        "installation-#{obj.installation.id}"
      end
    when User
      "user-#{obj.id}"
    when OauthApplication
      "app-#{obj.key}"
    when Integration
      "integration-#{obj.key}"
    when PublicKey
      "key-#{obj.id}"
    when ProximaServiceIdentity
      "psi-#{obj.service_name}-#{obj.tenant_shortcode}".downcase
    else
      obj.to_s
    end
  end
end
