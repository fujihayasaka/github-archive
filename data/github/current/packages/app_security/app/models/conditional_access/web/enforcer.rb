# typed: true
# frozen_string_literal: true

# This is the ApplicationController specific implementation of ConditionalAccess::Enforcer
# wired up with the policies to use in production.
#
# As of today, SAML hasn't been migrated to ConditionalAccess::Enforcer
class ConditionalAccess::Web::Enforcer < ConditionalAccess::Enforcer
  include ConditionalAccess::Web::Helpers
  include ::ConditionalAccess::Web::TwoFactorAuthnPolicy
  include ::ConditionalAccess::Web::EmuOwnershipPolicy
  include ::ConditionalAccess::Web::EmuVisibilityPolicy
  include ::ConditionalAccess::Web::TenantVerificationPolicy
  include ::ConditionalAccess::Web::EnterpriseAccessVerificationPolicy
  include ::ConditionalAccess::Web::IpAllowlistPolicy
  include ::ConditionalAccess::Web::ExternalConditionalAccessPolicy

  DEFAULT_POLICIES = [
    :enterprise_access_verification,
    :tenant_verification,
    :emu_visibility,
    :emu_ownership,
    :ip_allowlist,
    :two_factor,
    :external_conditional_access_policy
  ]

  def initialize(callback)
    super(callback, do_authzd_science: true)
  end

  # policies enabled through Conditional Access Policies framework (CAP)
  # will be enforced through enforce_conditional_access_policies method
  def conditional_access_policies
    DEFAULT_POLICIES
  end

  # Policies that are registered - may or may not
  # be included in the default policies
  def registered_policies
    DEFAULT_POLICIES
  end

  # Policies eligible to be compared to authzd policies
  def authzd_science_policies
    [
      :enterprise_access_verification,
      :tenant_verification,
      :emu_visibility,
      :emu_ownership,
      :ip_allowlist,
      :two_factor,
      :external_conditional_access_policy,
    ]
  end

  def authzd_enforcer_type
    "Web"
  end

  def location
    :web
  end
end
