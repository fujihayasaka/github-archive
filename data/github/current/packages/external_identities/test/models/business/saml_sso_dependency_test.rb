# typed: false
# frozen_string_literal: true

require "test_helper"

module BusinessSamlSsoDependencyNoSCIMSharedTests
  extend ActiveSupport::Concern

  included do
    context "#non_scim_managed_business?" do
      test "#non_scim_managed_business? returns false if the business is SCIM managed" do
        refute_predicate @business, :non_scim_managed_business?
      end
    end
  end
end

module BusinessSamlSsoDependencyWithSCIMSharedTests
  extend ActiveSupport::Concern

  included do
    context "#non_scim_managed_business?" do
      test "returns true if the business is not SCIM managed" do
        assert_predicate @business, :non_scim_managed_business?
      end
    end
  end
end

module BusinessSamlSsoDependencyNoGHESWithSCIMSharedTests
  extend ActiveSupport::Concern

  included do
    context "#enterprise_server_scim_enabled?" do
      test "returns false if the business is SCIM managed since private instance" do
        refute_predicate @business, :enterprise_server_scim_enabled?
      end
    end
  end
end

class BusinessSamlSsoDependencyTest < GitHub::TestCase
  include BusinessSamlSsoDependencyWithSCIMSharedTests
  include BusinessSamlSsoDependencyNoGHESWithSCIMSharedTests
  include AuthenticationHelpers::SAML

  fixtures do
    @provider = create :business_saml_provider
    @business = @provider.business
    @admin = @business.owners.first
    external_identity = create :external_identity, provider: @provider, user: @admin
    @admin_session = create :external_identity_session, external_identity: external_identity
  end

  setup do
    GitHub.stubs(:single_business_environment?).returns(false)
  end

  context "Business#saml_sso_enforced?" do
    test "returns false when in a single business environment" do
      GitHub.stubs(:single_business_environment?).returns(true)
      refute_predicate @business, :saml_sso_enforced?
    end

    test "returns false when no SAML provider is present for the business" do
      @business.saml_provider.destroy
      refute_predicate @business, :saml_sso_enforced?
    end

    test "returns true when a SAML provider is present" do
      assert_predicate @business.saml_provider, :present?
      assert_predicate @business, :saml_sso_enforced?
    end
  end

  context "Business#saml_sso_enabled?" do
    test "returns false when in a single business environment" do
      Business.destroy_all
      GitHub.stubs(:single_business_environment?).returns(true)
      business = create :business
      refute_predicate business, :saml_sso_enabled?
    end

    test "returns true in a single business environment and scim provisioning state disabled" do
      Business.destroy_all
      GitHub.stubs(:single_business_environment?).returns(true)
      business = create :business

      business.create_saml_provider \
        sso_url: "https://githubtest.okta.com/app/github_githubtestsamlorg_1/abcd1234/sso/saml",
        issuer: "http://okta.com/abcd1234",
        idp_certificate: Rails.root.join("test/fixtures/misc/saml/okta.pem").read

      refute_predicate business, :saml_sso_enabled?
    end

    test "returns true in a single business environment and scim provisioning state enabled" do
      Business.destroy_all
      GitHub.stubs(:single_business_environment?).returns(true)
      business = create :business

      provider = business.create_saml_provider \
        sso_url: "https://githubtest.okta.com/app/github_githubtestsamlorg_1/abcd1234/sso/saml",
        issuer: "http://okta.com/abcd1234",
        idp_certificate: Rails.root.join("test/fixtures/misc/saml/okta.pem").read
      provider.scim_provisioning_state = :scim_provisioning_state_enabled
      provider.save

      assert_predicate business, :saml_sso_enabled?
    end

    test "returns false when no SAML provider is present for the business" do
      @business.saml_provider.destroy
      refute_predicate @business, :saml_sso_enabled?
    end

    test "returns true when a SAML provider is present" do
      assert_predicate @business.saml_provider, :present?
      assert_predicate @business, :saml_sso_enabled?
    end
  end

  context "Business#external_identity_session_owner" do
    test "returns self" do
      assert_equal @business, @business.external_identity_session_owner
    end
  end

  context "#enterprise_server_scim_enabled?" do
    if GitHub.enterprise?
      test "return true when in a single business environment with scim enabled and saml provider" do
        setup_saml_auth_mode(with_scim: true)
        assert_predicate @business, :enterprise_server_scim_enabled?
      end

      test "returns false when in a single business environment without saml provider" do
        setup_saml_auth_mode(with_scim: true)
        @business.saml_provider.destroy

        @business.reload
        refute_predicate @business, :enterprise_server_scim_enabled?
      end
    else
      test "returns false when not in a single business environment" do
        refute_predicate @business, :enterprise_server_scim_enabled?
      end
    end
  end

  context "#saml_sso_requirement_met_by?" do
    test "returns true when SAML is not configured" do
      @business.saml_provider.destroy
      assert @business.saml_sso_requirement_met_by?(create(:user))
    end

    test "returns false when SAML is configured and the user does not have a linked external identity" do
      user = create(:user, login: "non-saml-member")

      refute @business.saml_sso_requirement_met_by?(user), "User without external identity should not meet the SAML enforcement requirement"
    end

    test "returns false when SAML is configured and the user is nil" do
      refute @business.saml_sso_requirement_met_by?(nil), "Nil user should not meet the SAML enforcement requirement"
    end

    test "returns true when SAML is enforced and the user has an external identity" do
      user = create(:user, login: "saml-member")
      create(:external_identity,
        provider: @business.saml_provider,
        user: user,
      )

      assert @business.saml_sso_requirement_met_by?(user), "User with external identity should meet the SAML enforcement requirement"
    end
  end

  context "#saml_sso_requirement_met_by_users?" do
    test "returns true when SAML is not configured" do
      @business.saml_provider.destroy

      user = create(:user)
      assert @business.saml_sso_requirement_met_by_users?([user].map(&:id))
    end

    test "returns false when SAML is configured and the user does not have a linked external identity" do
      user = create(:user, login: "non-saml-member")

      refute @business.saml_sso_requirement_met_by_users?([user].map(&:id)), "User without external identity should not meet the SAML enforcement requirement"
    end

    test "returns false when SAML is configured and the user is nil" do
      refute @business.saml_sso_requirement_met_by_users?(nil), "Nil user should not meet the SAML enforcement requirement"
    end

    test "returns true when SAML is enforced and the user has an external identity" do
      user = create(:user, login: "saml-member")
      create(:external_identity,
        provider: @business.saml_provider,
        user: user,
      )

      assert @business.saml_sso_requirement_met_by_users?([user].map(&:id)), "User with external identity should meet the SAML enforcement requirement"
    end
  end

  # adding redundant tests so we don't break default businesses inadvertently when moving from saml_dependency to external_provider dependency
  context "#external_sso_requirement_met_by?" do
    test "returns true when SAML is not configured" do
      @business.saml_provider.destroy
      assert @business.external_sso_requirement_met_by?(create(:user))
    end

    test "returns false when SAML is configured and the user does not have a linked external identity" do
      user = create(:user, login: "non-saml-member")

      refute @business.external_sso_requirement_met_by?(user), "User without external identity should not meet the SAML enforcement requirement"
    end

    test "returns false when SAML is configured and the user is nil" do
      refute @business.external_sso_requirement_met_by?(nil), "Nil user should not meet the SAML enforcement requirement"
    end

    test "returns true when SAML is enforced and the user has an external identity" do
      user = create(:user, login: "saml-member")
      create(:external_identity,
        provider: @business.saml_provider,
        user: user,
      )

      assert @business.external_sso_requirement_met_by?(user), "User with external identity should meet the SAML enforcement requirement"
    end
  end

  context "expire_all_enterprise_sessions!" do
    test "does nothing if saml user provisioning is disabled" do
      @business.saml_provider.update \
        provisioning_enabled: false,
        saml_deprovisioning_enabled: false

      assert_same_elements [@admin_session], @provider.external_identity_sessions.active

      expire_enterprise_sessions

      assert_same_elements [@admin_session], @provider.external_identity_sessions.active
    end

    test "does nothing if saml sso deprovisioning is disabled" do
      @business.saml_provider.update \
        provisioning_enabled: true,
        saml_deprovisioning_enabled: false

      assert_same_elements [@admin_session], @provider.external_identity_sessions.active

      expire_enterprise_sessions

      assert_same_elements [@admin_session], @provider.external_identity_sessions.active
    end

    test "immediately expires enterprise external identity sessions for the current user" do
      @business.saml_provider.update \
        provisioning_enabled: true,
        saml_deprovisioning_enabled: true
      org_admin = create(:user)
      org = create(:organization, admin: org_admin)
      @business.add_organization(org)
      external_identity = create :external_identity, provider: @provider, user: org_admin
      org_admin_session = create :external_identity_session, external_identity: external_identity

      assert_same_elements [@admin_session, org_admin_session], @provider.external_identity_sessions.active

      expire_enterprise_sessions

      assert_same_elements [@admin_session], @provider.external_identity_sessions.expired
      assert_same_elements [org_admin_session], @provider.external_identity_sessions.active
    end

    test "does nothing if the current user doesn't have an external identity" do
      @business.saml_provider.update \
        provisioning_enabled: true,
        saml_deprovisioning_enabled: true
      user = create(:user)
      assert_empty user.external_identities

      assert_no_difference("ExternalIdentitySession.active.count") do
        expire_enterprise_sessions(current_user: user)
      end
    end

    test "does not expire external identity sessions from another enterprise" do
      other_provider = create(:business_saml_provider)
      external_identity = create :external_identity, provider: other_provider, user: @admin
      other_admin_session = create :external_identity_session, external_identity: external_identity

      @business.saml_provider.update \
        provisioning_enabled: true,
        saml_deprovisioning_enabled: true

      assert_same_elements [other_admin_session], other_provider.external_identity_sessions.active

      expire_enterprise_sessions

      assert_same_elements [other_admin_session], other_provider.external_identity_sessions.active
    end

    test "does not expire external identity sessions from an organization outside the enterprise" do
      other_provider = create(:organization_saml_provider)
      other_provider.target.add_admin(@admin)
      external_identity = create :external_identity, provider: other_provider, user: @admin
      org_session = create :external_identity_session, external_identity: external_identity

      @business.saml_provider.update \
        provisioning_enabled: true,
        saml_deprovisioning_enabled: true

      assert_same_elements [org_session], other_provider.external_identity_sessions.active

      expire_enterprise_sessions

      assert_same_elements [org_session], other_provider.external_identity_sessions.active
    end

    test "does not expire external identity user sessions not associated with the enterprise account" do
      @business.saml_provider.update \
        provisioning_enabled: true,
        saml_deprovisioning_enabled: true

      other_admin_user_session = create :user_session, user: @admin

      assert_same_elements [@admin_session], @provider.external_identity_sessions.active
      assert other_admin_user_session.active?, "non-associated user session should be active"

      expire_enterprise_sessions

      assert_same_elements [@admin_session], @provider.external_identity_sessions.expired
      assert other_admin_user_session.active?, "non-associated user session should remain active"
    end

    test "enqueues a background job to expire active enterprise external identities" do
      @business.saml_provider.update \
        provisioning_enabled: true,
        saml_deprovisioning_enabled: true

      expire_enterprise_sessions

      assert_enqueued_with job: ExpireEnterpriseSessionsJob, args: [@business]
    end
  end

  def expire_enterprise_sessions(current_user: @admin)
    @business.expire_all_enterprise_sessions!(current_user: current_user)
  end
end

class EMUBusinessSamlSsoDependencyTest < GitHub::TestCase
  include BusinessSamlSsoDependencyNoSCIMSharedTests
  include BusinessSamlSsoDependencyNoGHESWithSCIMSharedTests

  fixtures do
    @business = create :business, :enterprise_managed
  end
end unless GitHub.single_business_environment?

class GHESWithSCIMBusinessSamlSsoDependencyTest < GitHub::TestCase
  include BusinessSamlSsoDependencyNoSCIMSharedTests
  include AuthenticationHelpers::SAML

  fixtures do
    setup_saml_auth_mode(with_scim: true)
    @business = create(:global_business)
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end

  context "#enterprise_server_scim_enabled?" do
    test "returns true if the business is SCIM managed" do
      assert_predicate @business, :enterprise_server_scim_enabled?
    end
  end

  context "#saml_sso_requirement_met_by?" do
    test "returns true when GHES SCIM is enabled" do
      user = create :user
      assert_empty user.external_identities

      assert @business.saml_sso_requirement_met_by?(user)
    end
  end

  context "#saml_sso_requirement_met_by_users?" do
    test "returns true when GHES SCIM is enabled" do
      user1 = create :user
      user2 = create :user
      assert_empty user1.external_identities
      assert_empty user2.external_identities

      assert @business.saml_sso_requirement_met_by_users?([user1, user2].map(&:id))
    end
  end
end if GitHub.single_business_environment?

class GHESNoSCIMBusinessSamlSsoDependencyTest < GitHub::TestCase
  include BusinessSamlSsoDependencyNoGHESWithSCIMSharedTests
  include BusinessSamlSsoDependencyWithSCIMSharedTests
  include AuthenticationHelpers::SAML

  fixtures do
    @business = create(:global_business)
  end

  setup do
    setup_saml_auth_mode
  end
end if GitHub.single_business_environment?
