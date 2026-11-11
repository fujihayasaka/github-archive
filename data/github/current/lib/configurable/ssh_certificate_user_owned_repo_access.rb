# typed: true
# frozen_string_literal: true

# Whether SSH certificates signed by a certificate authority
# owned by the target business can access user-owned repositories.
module Configurable
  module SshCertificateUserOwnedRepoAccess
    extend T::Helpers
    requires_ancestor { Configurable }

    KEY = "ssh_certificate_user_owned_repo_access".freeze

    def enable_ssh_certificate_user_owned_repo_access(actor)
      return unless config.enable!(KEY, actor)
      GitHub.instrument(
        "ssh_certificate_user_owned_repo_access.enable",
        { user: actor, business: self },
      )
    end

    def disable_ssh_certificate_user_owned_repo_access(actor)
      return unless config.delete(KEY, actor)
      GitHub.instrument(
        "ssh_certificate_user_owned_repo_access.disable",
        { user: actor, business: self },
      )
    end

    def ssh_certificate_user_owned_repo_access_enabled?
      # only available in GHES or EMU enterprises (GHEC and Proxima)
      return false unless GitHub.single_business_environment? || T.unsafe(self).enterprise_managed?

      ssh_enabled = if T.unsafe(self).respond_to?(:ssh_enabled?)
        T.unsafe(self).ssh_enabled?
      else
        GitHub.ssh_enabled?
      end
      ssh_enabled && config.enabled?(KEY)
    end

    def can_enable_ssh_certificate_user_owned_repo_access?
      return false unless GitHub.single_business_environment? || T.unsafe(self).enterprise_managed?
      ssh_enabled = if T.unsafe(self).respond_to?(:ssh_enabled?)
        T.unsafe(self).ssh_enabled?
      else
        GitHub.ssh_enabled?
      end
      ssh_enabled
    end
  end
end
