# typed: true
# frozen_string_literal: true

module Business::GettingStartedDependency
  include BusinessesHelper
  include GitHub::Memoizer

  extend T::Helpers

  requires_ancestor { Business }

  sig { returns(T::Boolean) }
  memoize def trial_with_organization?
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false unless trial?
    return true if organizations.any?
    false
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_invited_owner?
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false unless trial?
    admins(role: Business::OWNER_ROLE).count + pending_admin_invitations(role: Business::OWNER_ROLE).count >= 2
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_verified_identity_for_copilot?
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false unless trial?
    return false unless has_valid_payment_method?
    true
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_two_copilot_seats_assigned?
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false unless trial?
    copilot_user_ids.count >= 2
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_secret_scanning?
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false unless trial?

    business.organizations.any? do |org|
      org.repositories.any? do |repo|
        if SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_enabled?(repo)
          return true
        end
      end
    end
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_code_scanning?
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false unless trial?
    business.organizations.any? do |org|
      org.repositories.any? do |repo|
        return true if CodeSecurity::Features::AdvancedSecurityHelper.code_security_enabled?(repository: repo)
      end
    end
    false
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_saml_sso?
    return false unless trial?
    saml_sso_enabled?
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_readme?
    return false unless trial?
    business.long_description.present?
  end
end
