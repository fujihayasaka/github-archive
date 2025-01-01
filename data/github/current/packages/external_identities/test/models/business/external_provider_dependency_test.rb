# typed: true
# frozen_string_literal: true

require "test_helper"

module BusinessExternalProviderDependencySharedTests
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { GitHub::TestCase }

  included do
    T.bind(self, T.class_of(GitHub::TestCase))

    context "#external_provider_enabled?" do
      test "returns true for provider" do
        assert_predicate @enterprise.external_provider, :present?
        assert @enterprise.external_provider_enabled?
      end
    end

    context "#external_identity_session_owner" do
      test "returns self" do
        assert_equal @enterprise, @enterprise.external_identity_session_owner
      end
    end

    context "#external_provider" do
      test "returns provider attached to business" do
        assert_equal @enterprise.external_provider, @enterprise.saml_provider if @enterprise.saml_provider
        assert_equal @enterprise.external_provider, @enterprise.oidc_provider if @enterprise.oidc_provider
      end
    end

    context "#external_sso_requirement_met_by?" do
      test "returns true for scim enabled enterprise" do
        assert @enterprise.external_sso_requirement_met_by?(@owner)
      end
    end

    context "#external_sso_requirement_met_by_users?" do
      test "returns true for scim enabled enterprise" do
        assert @enterprise.external_sso_requirement_met_by_users?([@owner].map(&:id))
      end
    end

    context "#meets_sso_requirements?" do
      test "returns true when user meets SSO requirements" do
        assert @enterprise.meets_sso_requirements?(@owner)
      end

      test "returns false when user does not meet SSO requirements", skip_enterprise: true do
        refute @enterprise.meets_sso_requirements?(@non_member)
      end
    end
  end
end

class EmuSAMLBusinessExternalProviderDependencyTest < GitHub::TestCase
  include BusinessExternalProviderDependencySharedTests

  fixtures do
    @non_member = create :user
    @owner = create :emu, :owner, login: "owner"
    @enterprise = @owner.enterprise_managed_business
  end
end unless GitHub.single_business_environment?

class EmuOIDCBusinessExternalProviderDependencyTest < GitHub::TestCase
  include BusinessExternalProviderDependencySharedTests

  fixtures do
    @non_member = create :user
    @owner = create :emu, :owner, provider_type: :oidc, login: "owner"
    @enterprise = @owner.enterprise_managed_business
  end
end unless GitHub.single_business_environment?

class GhesWithSCIMBusinessExternalProviderDependencyTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  include BusinessExternalProviderDependencySharedTests

  fixtures do
    @non_member = create :user
    @owner = create :ghes_scim_user, :admin, login: "owner"
    @enterprise = @owner.external_identities.first.provider.business
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end
end if GitHub.single_business_environment?
