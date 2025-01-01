# typed: true
# frozen_string_literal: true

require "test_helper"

module OIDCEMUOrganizationSamlEnforcementPolicySharedTests
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { OrganizationSamlEnforcementPolicyTestCase }

  included do
    T.bind(self, T.class_of(OrganizationSamlEnforcementPolicyTestCase))

    context "OIDC EMU", skip_enterprise: true do
      context "filter_enforced" do
        test "user orgs are returned" do
          assert_equal [@emu_org2], Organization::SamlEnforcementPolicy.filter_enforced([@emu_org, @emu_org2], @emu_member)
        end

        test "user orgs are returned for guest collaborators" do
          assert_equal [@emu_org], Organization::SamlEnforcementPolicy.filter_enforced([@emu_org, @emu_org2], @guest_collaborator)
        end
      end
    end
  end
end

module SAMLEMUOrganizationSamlEnforcementPolicySharedTests
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { OrganizationSamlEnforcementPolicyTestCase }

  included do
    T.bind(self, T.class_of(OrganizationSamlEnforcementPolicyTestCase))

    context "filter_enforced" do
      context "SAML EMU", skip_enterprise: true do
        test "works for EMUs (all orgs are SAML enforced)" do
          assert_equal [@emu_org, @emu_org2], Organization::SamlEnforcementPolicy.filter_enforced([@emu_org, @emu_org2], @emu_member)
        end

        test "works for guest collaborators (all orgs are SAML enforced)" do
          assert_equal [@emu_org, @emu_org2], Organization::SamlEnforcementPolicy.filter_enforced([@emu_org, @emu_org2], @guest_collaborator)
        end

        test "exempts org to which user is outside collaborator" do
          emu_org_3 = create :organization, business: @emu_biz, admin: @emu_member
          repo = create(:repository, owner: emu_org_3)
          RepositoryInvitation.invite_to_repo_without_confirmation(@guest_collaborator, emu_org_3.owner, repo)

          refute_includes Organization::SamlEnforcementPolicy.filter_enforced([@emu_org, @emu_org2], @guest_collaborator), emu_org_3
        end
      end
    end
  end
end

module OrganizationSamlEnforcementPolicySharedTests
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { OrganizationSamlEnforcementPolicyTestCase }

  included do
    T.bind(self, T.class_of(OrganizationSamlEnforcementPolicyTestCase))

    test "not enforced without an org" do
      refute enforced?(org: nil, user: @unaffiliated)
    end

    test "not enforced without a user" do
      refute enforced?(org: @org, user: nil)
    end

    test "not enforced without saml sso" do
      refute enforced?(org: create(:organization, admin: @owner), user: @owner)
    end

    test "not enforced when user is not a member of the org" do
      refute enforced?(org: @org, user: @unaffiliated)
    end

    test "not enforced for user without external identity" do
      refute enforced?(org: @org, user: @member)
    end

    test "enforced for user with external identity" do
      create :external_identity, user: @member, provider: @provider
      assert enforced?(org: @org, user: @member)
    end

    test "not enforced for outside collaborators" do
      @provider.enforce!
      refute enforced?(org: @org, user: @collaborator)
    end

    test "enforced when provider requires enforcement" do
      @provider.enforce!
      assert enforced?(org: @org, user: @member)
    end

    context "filter_enforced" do
      context "organizations without business owners" do
        test "without saml are not enforced" do
          free_orgs = [@free_org_no_saml]

          assert_equal [], Organization::SamlEnforcementPolicy.filter_enforced(free_orgs, @unmapped_user)
          assert_equal [], Organization::SamlEnforcementPolicy.filter_enforced(free_orgs, @mapped_user)
          assert_equal [], Organization::SamlEnforcementPolicy.filter_enforced(free_orgs, @non_member)
        end

        test "are not enforced for non-member" do
          all_orgs = Organization.all.to_a

          assert_equal [], Organization::SamlEnforcementPolicy.filter_enforced(all_orgs, @non_member)
        end

        test "with enforced saml provider are enforced" do
          enforced_orgs = [@business_plus_org_enforced_saml]

          assert_equal [@business_plus_org_enforced_saml], Organization::SamlEnforcementPolicy.filter_enforced(enforced_orgs, @admin)
          assert_equal [@business_plus_org_enforced_saml], Organization::SamlEnforcementPolicy.filter_enforced(enforced_orgs, @mapped_user)

          # Even though the unmapped user can't really be a member of a SAML-enforced org,
          # we'd expect that if they did somehow end up being a member, SAML should be enforced on them.
          assert_equal [@business_plus_org_enforced_saml], Organization::SamlEnforcementPolicy.filter_enforced(enforced_orgs, @unmapped_user)
        end

        test "with external identity for user are enforced" do
          unenforced_orgs = [@business_plus_org_unenforced_saml]

          assert_equal [@business_plus_org_unenforced_saml], Organization::SamlEnforcementPolicy.filter_enforced(unenforced_orgs, @admin)
          assert_equal [@business_plus_org_unenforced_saml], Organization::SamlEnforcementPolicy.filter_enforced(unenforced_orgs, @mapped_user)
          assert_equal [], Organization::SamlEnforcementPolicy.filter_enforced(unenforced_orgs, @unmapped_user)
        end
      end

      unless GitHub.single_business_environment?
        context "organizations owned by a business" do
          test "trial business orgs that have saml are enforced" do
            owner = create :user
            business = create :business, :with_self_serve_payment, trial_expires_at: 1.month.from_now, owners: [owner]
            org = create :organization, plan: :business, admins: [owner]
            invite = create :business_organization_invitation, business: business, invitee: org, inviter: owner
            invite.accept owner
            invite.confirm owner
            saml_provider = create :organization_saml_provider, organization: org
            saml_provider.enforce!
            create :external_identity, user: owner, provider: saml_provider
            org.save
            org.reload

            trial_orgs = [org]

            assert_equal [org], Organization::SamlEnforcementPolicy.filter_enforced(trial_orgs, owner)
          end

          test "with no saml provider are not enforced" do
            business = create :business, owners: [create(:user)]
            org = create :business_plus_organization
            business.add_organization(org)
            member = create :user
            org.add_member(member)

            assert_equal [], Organization::SamlEnforcementPolicy.filter_enforced([org], member)
          end

          test "with saml provider are enforced" do
            business = create :business, owners: [create(:user)]
            business_provider = create :business_saml_provider, business: business
            org = create :business_plus_organization
            member = create :user
            org.add_member(member)
            business.add_organization(org)

            assert_equal [org], Organization::SamlEnforcementPolicy.filter_enforced([org], member)
          end

          test "SAML is not enforced on biz owners who are not members of the org" do
            owner = create :user
            member = create :user
            business = create :business, owners: [owner]
            business_provider = create :business_saml_provider, business: business
            create :external_identity, user: owner, provider: business_provider
            create :external_identity, user: member, provider: business_provider
            org = create :business_plus_organization
            business.add_organization(org)
            org.reload

            assert_equal [org], Organization::SamlEnforcementPolicy.filter_enforced([org], owner)
          end
        end
      end
    end

    unless GitHub.single_business_environment?
      test "enforces when parent business has saml sso" do
        business = create(:business, owners: [create(:user)])
        business_provider = create :business_saml_provider, business: business
        org = create :business_plus_organization
        member = create :user
        org.add_member(member)
        create :external_identity, user: member, provider: business_provider
        business.add_organization(org)
        assert enforced?(org: org.reload, user: member)
      end
    end
  end
end

class OrganizationSamlEnforcementPolicyTestCase < GitHub::TestCase
  def create_org(org_kind, saml_enabled:, saml_enforced:)
    org = create org_kind, admin: @admin

    org.add_member(@mapped_user)
    org.add_member(@unmapped_user)

    if saml_enabled
      saml_provider = create :organization_saml_provider, organization: org
      saml_provider.enforce! if saml_enforced
      create :external_identity, user: @mapped_user, provider: saml_provider
      create :external_identity, user: @admin, provider: saml_provider
    end

    org
  end

  def enforced?(org:, user:)
    Organization::SamlEnforcementPolicy.new(organization: org, user: user).enforced?
  end
end

class OIDCOrganizationSamlEnforcementPolicyTest < OrganizationSamlEnforcementPolicyTestCase
  include GitHub::LoggerHelper
  include OrganizationSamlEnforcementPolicySharedTests
  include OIDCEMUOrganizationSamlEnforcementPolicySharedTests

  fixtures do
    @provider = create(:organization_saml_provider)
    @org = @provider.organization
    @owner = @org.admin

    @member = create :user, login: "org-member"
    @org.add_member(@member)

    @collaborator = create :user, login: "org-collaborator"
    @org.add_member(@collaborator)
    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) { @org.convert_to_outside_collaborator!(@collaborator) }

    @unaffiliated = create :user, login: "unaffiliated"

    # For filter_enforced tests
    @admin = create :user
    @mapped_user = create :user
    @unmapped_user = create :user
    @non_member = create :user

    @free_org_no_saml = create_org :organization, saml_enabled: false, saml_enforced: false
    @business_plus_org_no_saml = create_org :business_plus_org, saml_enabled: false, saml_enforced: false
    @free_org_enforced_saml = create_org :organization, saml_enabled: true, saml_enforced: true
    @business_plus_org_enforced_saml = create_org :business_plus_org, saml_enabled: true, saml_enforced: true
    @free_org_unenforced_saml = create_org :organization, saml_enabled: true, saml_enforced: false
    @business_plus_org_unenforced_saml = create_org :business_plus_org, saml_enabled: true, saml_enforced: false

    unless GitHub.enterprise?
      @emu_owner = create :emu, :owner, provider_type: :oidc, login: "owner"
      @emu_biz = @emu_owner.enterprise_managed_business
      @emu_member = create(:emu, business: @emu_biz)
      @emu_org = create :organization, business: @emu_biz, admin: @emu_owner
      @emu_org2 = create :organization, business: @emu_biz, admin: @emu_member

      @guest_collaborator = create(:emu, :guest_collaborator, business: @emu_biz)
      @emu_org.add_member(@guest_collaborator)
    end
  end
end

class SAMLOrganizationSamlEnforcementPolicyTest < OrganizationSamlEnforcementPolicyTestCase
  include GitHub::LoggerHelper
  include OrganizationSamlEnforcementPolicySharedTests
  include SAMLEMUOrganizationSamlEnforcementPolicySharedTests

  fixtures do
    @provider = create(:organization_saml_provider)
    @org = @provider.organization
    @owner = @org.admin

    @member = create :user, login: "org-member"
    @org.add_member(@member)

    @collaborator = create :user, login: "org-collaborator"
    @org.add_member(@collaborator)
    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) { @org.convert_to_outside_collaborator!(@collaborator) }

    @unaffiliated = create :user, login: "unaffiliated"

    # For filter_enforced tests
    @admin = create :user
    @mapped_user = create :user
    @unmapped_user = create :user
    @non_member = create :user

    @free_org_no_saml = create_org :organization, saml_enabled: false, saml_enforced: false
    @business_plus_org_no_saml = create_org :business_plus_org, saml_enabled: false, saml_enforced: false
    @free_org_enforced_saml = create_org :organization, saml_enabled: true, saml_enforced: true
    @business_plus_org_enforced_saml = create_org :business_plus_org, saml_enabled: true, saml_enforced: true
    @free_org_unenforced_saml = create_org :organization, saml_enabled: true, saml_enforced: false
    @business_plus_org_unenforced_saml = create_org :business_plus_org, saml_enabled: true, saml_enforced: false

    unless GitHub.enterprise?
      @emu_owner = create :emu, :owner, login: "owner"
      @emu_biz = @emu_owner.enterprise_managed_business
      @emu_member = create(:emu, business: @emu_biz)
      @emu_org = create :organization, business: @emu_biz, admin: @emu_owner
      @emu_org2 = create :organization, business: @emu_biz, admin: @emu_member

      @guest_collaborator = create(:emu, :guest_collaborator, business: @emu_biz)
      @emu_org.add_member(@guest_collaborator)
    end
  end
end
