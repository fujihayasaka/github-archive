# typed: false
# frozen_string_literal: true

require "test_helper"

module BusinessExternalProviderDependencySharedTests
  def test_external_provider_enabled_returns_true_for_provider
    assert_predicate @enterprise.external_provider, :present?
    assert @enterprise.external_provider_enabled?
  end

  def test_external_identity_session_owner_returns_self
    assert_equal @enterprise, @enterprise.external_identity_session_owner
  end

  def test_external_provider_returns_provider_attached_to_business
    assert_equal @enterprise.external_provider, @enterprise.saml_provider if @enterprise.saml_provider
    assert_equal @enterprise.external_provider, @enterprise.oidc_provider if @enterprise.oidc_provider
  end

  def test_external_sso_requirement_met_by_returns_true_for_scim_enabled_enterprise
    assert @enterprise.external_sso_requirement_met_by?(@owner)
  end

  def test_external_sso_requirement_met_by_users_returns_true_for_scim_enabled_enterprise
    assert @enterprise.external_sso_requirement_met_by_users?([@owner].map(&:id))
  end
end

class EmuSAMLBusinessExternalProviderDependencyTest < GitHub::TestCase
  include BusinessExternalProviderDependencySharedTests

  fixtures do
    @owner = create :emu, :owner, login: "owner"
    @enterprise = @owner.enterprise_managed_business
  end
end unless GitHub.single_business_environment?

class EmuOIDCBusinessExternalProviderDependencyTest < GitHub::TestCase
  include BusinessExternalProviderDependencySharedTests

  fixtures do
    @owner = create :emu, :owner, provider_type: :oidc, login: "owner"
    @enterprise = @owner.enterprise_managed_business
  end
end unless GitHub.single_business_environment?

class GhesWithSCIMBusinessExternalProviderDependencyTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  include BusinessExternalProviderDependencySharedTests

  fixtures do
    @owner = create :ghes_scim_user, :admin, login: "owner"
    @enterprise = @owner.external_identities.first.provider.business
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end
end if GitHub.single_business_environment?
