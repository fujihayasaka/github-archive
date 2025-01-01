# typed: true
# frozen_string_literal: true

require "test_helper"
require "turboghas"

class BusinessLicenseCsvUsageBuilderTest < GitHub::TestCase
  include ExternalGroupHelpers

  fixtures do
    @business_admin = create :user, login: "business-admin"
    @business_admin.emails.each(&:verify!)
    @business = create(:business, owners: [@business_admin])
    @business_billing_manager = create :user, login: "business-billing-manager"
    @business_billing_manager.emails.each(&:verify!)
    @business.billing.add_manager(@business_billing_manager, actor: @business_admin)

    @business_invited_admin = create :user, login: "business-invited-admin"
    @business_invited_admin.emails.each(&:verify!)
    @business.invite_admin(user: @business_invited_admin, inviter: @business_admin, role: :owner) unless GitHub.multi_tenant_enterprise?

    @business_invited_admin_email = "invited-admin@example.com"
    @business.invite_admin(email: @business_invited_admin_email, inviter: @business_admin, role: :owner) unless GitHub.multi_tenant_enterprise?

    @organization_admin = create :user, login: "organization-admin"
    @organization = create(:organization, admin: @organization_admin)
    @business.add_organization @organization
    @organization.reload

    @other_org_admin = create :user, login: "other-org-admin"
    @other_org = create(:organization, admin: @other_org_admin)
    @business.add_organization @other_org
    @other_org.reload

    @rando = create :user, login: "rando"
    @private_repo = create(:private_repository, owner: @organization)

    @public_repo_member = create :user, login: "public-repo-member"
    @public_repo_invitee = create :user, login: "public-repo-invitee"
    @public_repo_invitee_email = "public-repo-invitee@example.com"
    public_repo = create(:public_repository, owner: @organization)
    public_repo.add_member(@public_repo_member)
    RepositoryInvitation.invite_to_repo @public_repo_invitee, @organization_admin, public_repo
    RepositoryInvitation.invite_to_repo_by_email @public_repo_invitee_email, @organization_admin, public_repo

    @enterprise_installation = create(:enterprise_installation, owner: @business)

    unless GitHub.single_business_environment?
      @emu = create(:emu, :owner)
      @emu_business = @emu.enterprise_managed_business
      @emu2 = create(:emu, :owner, business: @emu_business)
      @emu_business_org = create :enterprise_linked_organization, business: @emu_business, admin: @emu
      @emu_business_org.add_member(@emu2)
      @emu_business_repo = create(:private_repository, owner: @emu_business_org)
    end

    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob
  end

  setup do
    enable_cache_storage
    reset_cache
    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob

    attributer = Business::LicenseAttributer.new(@business)
    @licensed_roles_hash = Business::LicenseCsvUsageBuilder.new(attributer).process
    attributer.options[:include_nonlicensed_roles] = true
    @nonlicensed_roles_hash = Business::LicenseCsvUsageBuilder.new(attributer).process

    Billing::Platform::Api::Client.any_instance
        .stubs(:get_subscribed_items)
        .returns({ subscribedItems: [] })
  end

  teardown do
    disable_cache_storage
  end

  def hash_for_user(license_hash, user)
    key = GitHub.multi_tenant_enterprise? ? :github_login : :github_com_login

    case user
    when ::User
      license_hash[:users].find do |users|
        users[key] == user.display_login
      end
    when ::String
      license_hash[:users].find do |users|
        users[key] == user
      end
    end
  end

  def add_variety_of_users_to_business
    # Standard user
    @organization.add_member(create(:user))

    # Invited user
    @organization.invite(create(:user), inviter: @organization_admin)

    # Invited user by email
    @organization.invite(email: "variety_org_invite@example.com", inviter: @organization_admin)

    # Repository invitation
    RepositoryInvitation.invite_to_repo create(:user), @organization_admin, @private_repo

    # Repository invitatin by email
    RepositoryInvitation.invite_to_repo_by_email "variety_repo_invite@example.com", @organization_admin, @private_repo

    # Outside collaborators
    @private_repo.add_member(create(:user))

    # User based business user account
    create(:business_user_account, business: @business, user: create(:user), roles: [:server_member])

    # Email based business user account with blank login
    create(:business_user_account, business: @business, user: nil, login: "", roles: [:server_member]).tap do |business_user_account|
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: "example@example.com",
        primary: true,
      )
    end

    # GHES-only user with different primary email addresses on different instances
    ghes_user2_email = "variety-ghes-user2@example.com"
    ghes_user2_email2 = "variety-a-ghes-user2@example.com"
    ghes_user2_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act,
      email: ghes_user2_email, primary: true

    ghes_user2_bus_act = create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user2_act],
      login: ghes_user2_email, roles: [:server_member]

    enterprise_installation2 = create(:enterprise_installation, owner: @business)
    ghes_user2_act2 = create :enterprise_installation_user_account,
      enterprise_installation: enterprise_installation2,
      site_admin: true,
      business_user_account: ghes_user2_bus_act

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act2,
      email: ghes_user2_email2, primary: true

    # Email based business user account with populated login
    create(:business_user_account, business: @business, user: nil, login: "variety_email_bua", roles: [:server_member]).tap do |business_user_account|
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: "variety_email_bua@example.com",
        primary: true,
      )
    end

    # Business user account with blank login and no emails
    create(:business_user_account, business: @business, user: nil, login: "", roles: [:server_member]).tap do |business_user_account|
      create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account
      )
    end

    # Business user account with populated login and no emails
    create(:business_user_account, business: @business, user: nil, login: "variety_no_email_bua", roles: [:server_member]).tap do |business_user_account|
      create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account
      )
    end

    # Business user account with only secondary email
    create(:business_user_account, business: @business, user: nil, roles: [:server_member]).tap do |business_user_account|
      enterprise_installation_user_account = create(
        :enterprise_installation_user_account,
        enterprise_installation: @enterprise_installation,
        business_user_account: business_user_account
      )
      create(
        :enterprise_installation_user_account_email,
        enterprise_installation_user_account: enterprise_installation_user_account,
        email: "example@example.com",
        primary: false
      )
    end

    # Bundled license assignments
    create(:enterprise_agreement, :visual_studio_bundle, business: @business)

    # Assignment without user
    create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "variety_assignment_wo_user@example.com")

    # User assignment
    create(:licensing_bundled_license_assignment, business: @business, user: create(:user), email: "variety_assignment_user@example.com")

    # Revoked assignment
    create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "variety_assignment_revoked@example.com", revoked: true)

    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob
  end

  # Clear the cache of the attributer
  def fresh_attributer(include_nonlicensed_roles: false)
    @business = Business.find(@business.id)
    Business::LicenseAttributer.new(@business, options: { include_nonlicensed_roles: include_nonlicensed_roles })
  end

  context "nonlicensed roles usage" do
    test "includes business admins as nonlicensed role" do
      refute hash_for_user(@licensed_roles_hash, @business_admin)
      assert hash_for_user(@nonlicensed_roles_hash, @business_admin)
      assert_nil hash_for_user(@nonlicensed_roles_hash, @business_admin)[:license_type]
    end unless GitHub.multi_tenant_enterprise?

    test "includes business billing managers as nonlicensed role" do
      refute hash_for_user(@licensed_roles_hash, @business_billing_manager)
      assert hash_for_user(@nonlicensed_roles_hash, @business_billing_manager)
      assert_nil hash_for_user(@nonlicensed_roles_hash, @business_billing_manager)[:license_type]
    end unless GitHub.multi_tenant_enterprise?

    test "includes pending business admin invitations as nonlicensed role" do
      refute hash_for_user(@licensed_roles_hash, @business_invited_admin)
      assert hash_for_user(@nonlicensed_roles_hash, @business_invited_admin)
      assert_nil hash_for_user(@nonlicensed_roles_hash, @business_invited_admin)[:license_type]
    end unless GitHub.multi_tenant_enterprise?

    test "includes pending business admins invited by email as nonlicensed role" do
      refute hash_for_user(@licensed_roles_hash, @business_invited_admin_email)
      assert hash_for_user(@nonlicensed_roles_hash, @business_invited_admin_email)
      assert_nil hash_for_user(@nonlicensed_roles_hash, @business_invited_admin_email)[:license_type]
    end unless GitHub.multi_tenant_enterprise?

    test "includes public repository outside collaborators as nonlicensed role" do
      refute hash_for_user(@licensed_roles_hash, @public_repo_member)
      assert hash_for_user(@nonlicensed_roles_hash, @public_repo_member)
      assert_nil hash_for_user(@nonlicensed_roles_hash, @public_repo_member)[:license_type]
    end unless GitHub.multi_tenant_enterprise?

    test "includes public repositories invited users as nonlicensed role" do
      refute hash_for_user(@licensed_roles_hash, @public_repo_invitee)
      assert hash_for_user(@nonlicensed_roles_hash, @public_repo_invitee)
      assert_nil hash_for_user(@nonlicensed_roles_hash, @public_repo_invitee)[:license_type]
    end unless GitHub.multi_tenant_enterprise?

    test "includes public repositories users invited by email as nonlicensed role" do
      refute hash_for_user(@licensed_roles_hash, @public_repo_invitee_email)
      assert hash_for_user(@nonlicensed_roles_hash, @public_repo_invitee_email)
      assert_nil hash_for_user(@nonlicensed_roles_hash, @public_repo_invitee_email)[:license_type]
    end unless GitHub.multi_tenant_enterprise?

    test "shows licensed members with additional nonlicensed roles as licensed" do
      business_member = create(:user)
      @organization.add_member(business_member)

      other_public_repo = create(:public_repository, owner: @other_org)
      other_public_repo.add_member(business_member)

      # User is now member of the organization and has a public repository outside collaborator role
      licensed_roles_hash = Business::LicenseAttributer.new(@business).license_usage_hash
      nonlicensed_roles_hash = Business::LicenseAttributer.new(@business,
        options: { include_nonlicensed_roles: true }).license_usage_hash

      assert hash_for_user(licensed_roles_hash, business_member)
      assert hash_for_user(nonlicensed_roles_hash, business_member)
      assert hash_for_user(nonlicensed_roles_hash, business_member)[:license_type], "Enterprise"
    end unless GitHub.multi_tenant_enterprise?

    # It is not documented if bundled license invitations should consume a license. Current behavior is for
    # them to not consume a license. This test documents that existing behavior.
    test "includes bundled license invitations for volume licensed businesses as nonlicensed role" do
      create(:enterprise_agreement, :visual_studio_bundle, business: @business)

      # Note - this user is not invited to an org. This is a bundled license associated to the business only.
      bla_invitation = create :licensing_bundled_license_assignment, business_id: @business.id,
        email: "invited-vss@example.com"

      vl_licensed_roles_hash = Business::LicenseAttributer.new(@business).license_usage_hash
      vl_nonlicensed_roles_hash = Business::LicenseAttributer.new(@business,
        options: { include_nonlicensed_roles: true }).license_usage_hash

      # Do not consume a license in the licensed roles hash
      refute hash_for_user(vl_licensed_roles_hash, bla_invitation.email)

      # Do not show as consuming license in members hash
      assert hash_for_user(vl_nonlicensed_roles_hash, bla_invitation.email)
      assert_nil hash_for_user(vl_nonlicensed_roles_hash, bla_invitation.email)[:license_type]
    end unless GitHub.multi_tenant_enterprise?

    context "metered GHE" do
      test "returns error when billing platform is unavailable" do
        @business.customer.update(metered_plan: true)
        attributer = Business::LicenseAttributer.new(@business, options: { include_users_removed_this_cycle: true })

        attributer.billing_platform_client
          .stubs(:get_subscribed_items)
          .returns(Billing::Platform::Api::Error.new("Test error"))

        assert_raises Billing::Platform::Api::Error do
          hash = Business::LicenseCsvUsageBuilder.new(attributer).process
        end
      end

      test "includes user invited to be an organization member in nonlicensed roles" do
        @business.customer.update(metered_plan: true)
        invited_user = create(:user)
        @organization.invite(invited_user, inviter: @organization_admin)

        licensed_roles_hash = Business::LicenseAttributer.new(@business).license_usage_hash
        nonlicensed_roles_hash = Business::LicenseAttributer.new(@business,
          options: { include_nonlicensed_roles: true }).license_usage_hash

        refute hash_for_user(licensed_roles_hash, invited_user)

        assert hash_for_user(nonlicensed_roles_hash, invited_user)
        assert_nil hash_for_user(nonlicensed_roles_hash, invited_user)[:license_type]
      end unless GitHub.multi_tenant_enterprise?

      test "includes email invited to be an organization member in nonlicensed roles" do
        @business.customer.update(metered_plan: true)
        invited_email = "invited@example.com"
        @organization.invite(email: invited_email, inviter: @organization_admin)

        licensed_roles_hash = Business::LicenseAttributer.new(@business).license_usage_hash
        nonlicensed_roles_hash = Business::LicenseAttributer.new(@business,
          options: { include_nonlicensed_roles: true }).license_usage_hash

        refute hash_for_user(licensed_roles_hash, invited_email)

        assert hash_for_user(nonlicensed_roles_hash, invited_email)
        assert_nil hash_for_user(nonlicensed_roles_hash, invited_email)[:license_type]
      end unless GitHub.multi_tenant_enterprise?

      test "includes user invited to be outside collaborator in nonlicensed roles" do
        @business.customer.update(metered_plan: true)
        invited_collaborator = create(:user)
        RepositoryInvitation.invite_to_repo invited_collaborator, @organization_admin, @private_repo

        licensed_roles_hash = Business::LicenseAttributer.new(@business).license_usage_hash
        nonlicensed_roles_hash = Business::LicenseAttributer.new(@business,
          options: { include_nonlicensed_roles: true }).license_usage_hash

        refute hash_for_user(licensed_roles_hash, invited_collaborator)

        assert hash_for_user(nonlicensed_roles_hash, invited_collaborator)
        assert_nil hash_for_user(nonlicensed_roles_hash, invited_collaborator)[:license_type]
      end unless GitHub.multi_tenant_enterprise?

      test "includes email invited to be outside collaborator in nonlicensed roles" do
        @business.customer.update(metered_plan: true)
        invited_email = "invited@example.com"
        RepositoryInvitation.invite_to_repo_by_email invited_email, @organization_admin, @private_repo

        licensed_roles_hash = Business::LicenseAttributer.new(@business).license_usage_hash
        nonlicensed_roles_hash = Business::LicenseAttributer.new(@business,
          options: { include_nonlicensed_roles: true }).license_usage_hash

        refute hash_for_user(licensed_roles_hash, invited_email)
        assert hash_for_user(nonlicensed_roles_hash, invited_email)
        assert_nil hash_for_user(nonlicensed_roles_hash, invited_email)[:license_type]
      end unless GitHub.multi_tenant_enterprise?
    end
  end
end if GitHub.billing_enabled? || GitHub.multi_tenant_enterprise?

# We test the Business::LicenseAttributer.license_usage_hash in it's own test case
# because it requires a lot of construction for all of the types of matching tested
# and it's easier to test and maintain it all in one place free of everything else.
class BusinessLicenseCsvUsageBuilderProcess < GitHub::TestCase
  fixtures do
    @org_admin = create(:user, :two_factor_enabled, login: "org-admin")
    @organization = create(:organization, admin: @org_admin)
    @organization2 = create(:organization, admin: @org_admin)
    @private_repo = create(:private_repository, owner: @organization)
    @business = create(:business, organizations: [@organization, @organization2])
    @enterprise_installation = create(:enterprise_installation, owner: @business)
    @enterprise_installation2 = create(:enterprise_installation, owner: @business)
  end

  test "returns a hash indicating no license usage when no users in business" do
    business = create(:business)
    attributer = Business::LicenseAttributer.new(business)
    hash = Business::LicenseCsvUsageBuilder.new(attributer).process

    assert_equal hash[:total_seats_consumed], 0
    assert_empty hash[:users]
  end

  test "returns the correct number of users for large enterprises" do
    Business::LicenseCsvUsageBuilder.stub_const(:MAX_USER_PROFILE_QUERIES, 3) do
      create_list(:user, 10).each { |u| @organization.add_member(u) }

      attributer = Business::LicenseAttributer.new(@business)
      hash = Business::LicenseCsvUsageBuilder.new(attributer).process
      assert_equal hash[:users].count, 11 # 10 users + 1 admin
    end
  end

  test "returns correct columns for multi tenant enterprise" do
    Business::LicenseCsvUsageBuilder.stub_const(:MAX_USER_PROFILE_QUERIES, 3) do
      create_list(:user, 1).each { |u| @organization.add_member(u) }

      attributer = Business::LicenseAttributer.new(@business)
      hash = Business::LicenseCsvUsageBuilder.new(attributer).process
      keys = hash[:users][0].keys
      assert keys.include?(:github_name)
      assert keys.include?(:github_login)
      refute keys.include?(:github_com_profile)
      refute keys.include?(:github_com_two_factor_auth_required_by_date)
    end
  end if GitHub.multi_tenant_enterprise?

  test "returns a hash for all types of users in business" do
    create(:enterprise_agreement, :visual_studio_bundle, business: @business)

    verified_org_domain = create(:verifiable_domain, owner: @organization, domain: "example.com", verified: true)
    verified_bus_domain = create(:verifiable_domain, owner: @business, domain: "xyz.lol", verified: true)
    # These should not appear anywhere in the hash
    approved_org_domain = create(:verifiable_domain, owner: @organization, domain: "org-approved.com", approved: true)
    approved_bus_domain = create(:verifiable_domain, owner: @business, domain: "bus-approved.com", approved: true)

    # Org admin - tweak profile and verify email
    create(:profile, name: "Org Admin", user: @org_admin)
    org_admin_verified_email = "org-admin@xyz.lol"
    @org_admin.add_email(org_admin_verified_email).verify!
    @org_admin.add_email("admin@org-approved.com").verify!

    # VSS user
    vss_user = create(:user, login: "vss-user")
    create(:profile, name: "VSS User", user: vss_user)
    @organization.add_member(vss_user)
    vss_user_bbla = create(:licensing_bundled_license_assignment, user: vss_user, business: @business)

    # Enterprise user that has everything:
    # - a SAML NameID,
    # - a verified org-level domain email,
    # - a business-level approved domain email,
    # - is a GHES user on multiple instances, with multiple emails on one instance,
    # - is the org's billing manager
    # - a pending org invite
    ent_user = create(:user, login: "ent-user")
    create(:profile, name: "Enterprise User", user: ent_user)
    ent_user_email = "ent-user@example.com"
    ent_user_ano_email = "ent-user@another.com"
    ent_user.add_email(ent_user_email).verify!
    ent_user.add_email("ent-user@bus-approved.com").verify!
    @organization.add_member(ent_user)
    @organization2.invite(ent_user, inviter: @org_admin)
    Organization::BillingManagement.new(@organization).add_manager(ent_user, actor: @org_admin)
    provider = create :organization_saml_provider, organization: @organization
    ent_user_nameid = "ent-user-NameID"
    saml_user_data = Platform::Provisioning::SamlUserData.new([
      { "name" => "NameID", "value" => ent_user_nameid },
    ])
    create(:external_identity, provider: provider, user: ent_user, saml_user_data: saml_user_data)

    ent_inst_user_act = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation,
      site_admin: true,
      business_user_account: ent_user.business_user_accounts.first,
      using_advanced_security: true

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act,
      email: ent_user_email, primary: true

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act,
      email: ent_user_ano_email, primary: false

    ent_inst_user_act2 = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation2,
      site_admin: true,
      business_user_account: ent_user.business_user_accounts.first,
      using_advanced_security: true

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act2,
      email: "ent-user@example.com", primary: true

    # GHES-only user with a primary email
    ghes_user_email = "ghes-user@example.com"
    ghes_user_act = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation,
      using_advanced_security: true

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user_act,
      email: ghes_user_email, primary: true

    create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user_act],
      login: ghes_user_email, roles: [:server_member]

    # GHES-only user without a primary email
    noemail_ghes = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation,
      using_advanced_security: true

    create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [noemail_ghes],
      login: "user-#{noemail_ghes.remote_user_id}", roles: [:server_member]

    # GHES-only user with different primary email addresses on different instances
    ghes_user2_email = "ghes-user2@example.com"
    ghes_user2_email2 = "a-ghes-user2@example.com"
    ghes_user2_act = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act,
      email: ghes_user2_email, primary: true

    ghes_user2_bus_act = create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user2_act],
      login: ghes_user2_email, roles: [:server_member]

    ghes_user2_act2 =  create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation2,
      site_admin: true,
      business_user_account: ghes_user2_bus_act

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act2,
      email: ghes_user2_email2, primary: true

    # GHES user which matches a VSS user
    ghes_vss_user_email = "ghes-vss@example.com"
    ghes_vss_user = create(:user, login: "ghes-vss-user", email: ghes_vss_user_email)
    create(:profile, name: "GHES VSS User", user: ghes_vss_user)
    @business.add_user_accounts([ghes_vss_user.id])
    ghes_vss_user_bbla = create :licensing_bundled_license_assignment,
      user: ghes_vss_user, email: ghes_vss_user_email, business: @business

    ghes_vss_user_act = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation,
      business_user_account: ghes_vss_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_vss_user_act,
      email: ghes_vss_user_email, primary: true

    # User invited to an org with pending invitation
    org_invited_user = create(:user, login: "org-invited-user")
    create(:profile, name: "Org Invited User", user: org_invited_user)
    @organization.invite(org_invited_user, inviter: @org_admin)

    # Org invite by email without a corresponding user
    org_invite_email = "test@invite.com"
    @organization.invite(email: org_invite_email, inviter: @org_admin)

    # Private org repo with pending outside collaborator user invite
    outside_collab_user_pending = create(:user, login: "outside-collab-user-pending")
    create(:repository_invitation, repository: @private_repo, invitee: outside_collab_user_pending)

    # Private org repo with accepted outside collaborator user invite
    outside_collab_user_accepted = create(:user, login: "outside-collab-user-accepted")
    three_weeks_from_now = 3.weeks.from_now.utc
    TwoFactorRequirementMetadata.create!(user: outside_collab_user_accepted, requirement_reason: "test", required_by: three_weeks_from_now, state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:warning])
    create(:repository_invitation, repository: @private_repo, invitee: outside_collab_user_accepted).accept!

    # Org invite by and VSS assigned email address
    vss_org_invite_email = "vss-org@invite.com"
    @organization.invite(email: vss_org_invite_email, inviter: @org_admin)
    create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "vss-org@invite.com")

    # GHES-only user that matches a deleted dotcom/GHEC user - this is a very rare edge case and will result in an
    # EnterpriseInstallationAccount linked to a BusinessUserAccount that no longer exists until the next license sync.
    deleted_user_email = "deleted-user@example.com"
    deleted_user = create(:user, login: "deleted-user")
    deleted_user.add_email(deleted_user_email).verify!
    del_user_act = create :enterprise_installation_user_account, :ghas_connect,
      enterprise_installation: @enterprise_installation,
      login: deleted_user.display_login
    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: del_user_act,
      email: deleted_user_email, primary: true
    create :business_user_account, business: @business, user: deleted_user,
      enterprise_installation_user_accounts: [del_user_act],
      login: deleted_user, roles: [:server_member]
    deleted_user.destroy!

    perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob])
    @business = Business.find(@business.id)
    attributer = Business::LicenseAttributer.new(@business)
    hash = Business::LicenseCsvUsageBuilder.new(attributer).process

    assert_equal 12, hash[:total_seats_consumed]
    assert_equal 12, hash[:users].size

    expected = [{
      github_com_login: @org_admin.display_login,
      github_com_name: @org_admin.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(@org_admin),
      github_com_member_roles:
        [@organization.name + ":Owner", @organization2.name + ":Owner"].sort,
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [org_admin_verified_email],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: true,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: vss_user.display_login,
      github_com_name: vss_user.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: ViewModel::URLs.new.user_url(vss_user),
      github_com_member_roles: [@organization.name + ":Member"],
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: "Matched to Cloud",
      visual_studio_subscription_email: vss_user_bbla.email,
      total_user_accounts: 1
    },
    {
      github_com_login: ent_user.display_login,
      github_com_name: ent_user.profile.name,
      enterprise_server_user_ids: [
        "#{ent_inst_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Owner",
        "#{ent_inst_user_act2.remote_user_id}:#{@enterprise_installation2.host_name}:Owner"
      ].sort,
      github_com_user: true,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(ent_user),
      github_com_member_roles: [@organization.name + ":Billing manager"],
      github_com_enterprise_roles: ["Member", "Pending invitation"],
      github_com_verified_domain_emails: [ent_user_email],
      github_com_saml_name_id: ent_user_nameid,
      github_com_orgs_with_pending_invites: [@organization2.name],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ent_user_email].sort,
      enterprise_server_advanced_security_user_ids: [
        "#{ent_inst_user_act.remote_user_id}:#{@enterprise_installation.host_name}",
        "#{ent_inst_user_act2.remote_user_id}:#{@enterprise_installation2.host_name}",
      ].sort,
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 3
    },
    {
      github_com_login: ghes_vss_user.display_login,
      github_com_name: ghes_vss_user.profile.name,
      enterprise_server_user_ids: ["#{ghes_vss_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: true,
      enterprise_server_user: true,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: ViewModel::URLs.new.user_url(ghes_vss_user),
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [ghes_vss_user_email],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_vss_user_email],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: "Matched to Cloud + Server",
      visual_studio_subscription_email: ghes_vss_user_email,
      total_user_accounts: 2
    },
    {
      github_com_login: org_invited_user.display_login,
      github_com_name: org_invited_user.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(org_invited_user),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: outside_collab_user_pending.display_login,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(outside_collab_user_pending),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending outside collaborator invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: outside_collab_user_accepted.display_login,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(outside_collab_user_accepted),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Outside collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: three_weeks_from_now.strftime("%Y-%m-%d"),
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1,
    },
    { # ghes-only user with different primary email addresses on different instances
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: [
        "#{ghes_user2_act.remote_user_id}:#{@enterprise_installation.host_name}:Member",
        "#{ghes_user2_act2.remote_user_id}:#{@enterprise_installation.host_name}:Owner"
      ].sort,
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_user2_email, ghes_user2_email2].sort,
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 2
    },
    { # ghes-only user with a primary email
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: ["#{ghes_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_user_email],
      enterprise_server_advanced_security_user_ids: ["#{ghes_user_act.remote_user_id}:#{@enterprise_installation.host_name}"],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # org invite by email without a corresponding user
      github_com_login: org_invite_email,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 0
    },
    { # ghes-only user without a primary email
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: ["#{noemail_ghes.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # org invite by email using an allocated VSS license
      github_com_login: "vss-org@invite.com",
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      enterprise_server_advanced_security_user_ids: [],
      visual_studio_license_status: "Pending Invitation",
      visual_studio_subscription_email: "vss-org@invite.com",
      total_user_accounts: 0
    }]

    0..expected.size.times do |i|
      assert_equal expected[i], hash[:users][i], "Failed to match row #{i + 1}"
    end
  end

  test "returns correct hash on pagination edge cases" do
    create(:enterprise_agreement, :visual_studio_bundle, business: @business)

    verified_org_domain = create(:verifiable_domain, owner: @organization, domain: "example.com", verified: true)
    verified_bus_domain = create(:verifiable_domain, owner: @business, domain: "xyz.lol", verified: true)

    # Org admin - tweak profile and verify email
    create(:profile, name: "Org Admin", user: @org_admin)
    org_admin_verified_email = "org-admin@xyz.lol"
    @org_admin.add_email(org_admin_verified_email).verify!

    # VSS user
    vss_user = create(:user, login: "vss-user")
    create(:profile, name: "VSS User", user: vss_user)
    @organization.add_member(vss_user)
    vss_user_bbla = create(:licensing_bundled_license_assignment, user: vss_user, business: @business)

    # Enterprise user that has everything:
    # - a SAML NameID,
    # - a verified org-level domain email,
    # - is a GHES user on multiple instances, with multiple emails on one instance,
    # - is the org's billing manager
    # - a pending org invite
    ent_user = create(:user, login: "ent-user")
    create(:profile, name: "Enterprise User", user: ent_user)
    ent_user_email = "ent-user@example.com"
    ent_user_ano_email = "ent-user@another.com"
    ent_user.add_email(ent_user_email).verify!
    @organization.add_member(ent_user)
    @organization2.invite(ent_user, inviter: @org_admin)
    Organization::BillingManagement.new(@organization).add_manager(ent_user, actor: @org_admin)
    provider = create :organization_saml_provider, organization: @organization
    ent_user_nameid = "ent-user-NameID"
    saml_user_data = Platform::Provisioning::SamlUserData.new([
      { "name" => "NameID", "value" => ent_user_nameid },
    ])
    create(:external_identity, provider: provider, user: ent_user, saml_user_data: saml_user_data)

    ent_inst_user_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation,
      site_admin: true,
      business_user_account: ent_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act,
      email: ent_user_email, primary: true

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act,
      email: ent_user_ano_email, primary: false

    ent_inst_user_act2 = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      site_admin: true,
      business_user_account: ent_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act2,
      email: "ent-user@example.com", primary: true

    # GHES-only user with a primary email
    ghes_user_email = "ghes-user@example.com"
    ghes_user_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user_act,
      email: ghes_user_email, primary: true

    create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user_act],
      login: ghes_user_email, roles: [:server_member]

    # GHES-only user without a primary email
    noemail_ghes = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation

    create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [noemail_ghes],
      login: "user-#{noemail_ghes.remote_user_id}", roles: [:server_member]

    # GHES-only user with different primary email addresses on different instances
    ghes_user2_email = "ghes-user2@example.com"
    ghes_user2_email2 = "a-ghes-user2@example.com"
    ghes_user2_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation,
      login: "a-ghes-user2"

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act,
      email: ghes_user2_email, primary: true

    ghes_user2_bus_act = create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user2_act],
      login: ghes_user2_email, roles: [:server_member]

    ghes_user2_act2 =  create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      site_admin: true,
      business_user_account: ghes_user2_bus_act,
      login: "a-ghes-user2-site-admin"

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act2,
      email: ghes_user2_email2, primary: true

    # GHES user which matches a VSS user
    ghes_vss_user_email = "ghes-vss@example.com"
    ghes_vss_user = create(:user, login: "ghes-vss-user", email: ghes_vss_user_email)
    create(:profile, name: "GHES VSS User", user: ghes_vss_user)
    @business.add_user_accounts([ghes_vss_user.id])
    ghes_vss_user_bbla = create :licensing_bundled_license_assignment,
      user: ghes_vss_user, email: ghes_vss_user_email, business: @business

    ghes_vss_user_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation,
      business_user_account: ghes_vss_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_vss_user_act,
      email: ghes_vss_user_email, primary: true

    # User invited to an org with pending invitation
    org_invited_user = create(:user, login: "org-invited-user")
    create(:profile, name: "Org Invited User", user: org_invited_user)
    @organization.invite(org_invited_user, inviter: @org_admin)

    # Org invite by email without a corresponding user
    org_invite_email = "test@invite.com"
    @organization.invite(email: org_invite_email, inviter: @org_admin)

    # Private org repo with pending outside collaborator user invite
    outside_collab_user_pending = create(:user, login: "outside-collab-user-pending")
    create(:repository_invitation, repository: @private_repo, invitee: outside_collab_user_pending)

    # Private org repo with accepted outside collaborator user invite
    outside_collab_user_accepted = create(:user, login: "outside-collab-user-accepted")
    create(:repository_invitation, repository: @private_repo, invitee: outside_collab_user_accepted).accept!

    # Org invite by and VSS assigned email address
    vss_org_invite_email = "vss-org@invite.com"
    @organization.invite(email: vss_org_invite_email, inviter: @org_admin)
    create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "vss-org@invite.com")

    perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob])
    @business = Business.find(@business.id)
    attributer = Business::LicenseAttributer.new(@business)
    hash_page_less_than_0 = Business::LicenseCsvUsageBuilder.new(attributer).process(pagination: true, page: -1)
    # This should have only six pages as we have 12 elements; but we are requesting page 7
    # We should get a result without any users present.
    hash_page_beyond_last_page = Business::LicenseCsvUsageBuilder.new(attributer).process(pagination: true, page: 7, per_page: 2)

    expected_full_hash = [{
      github_com_login: @org_admin.display_login,
      github_com_name: @org_admin.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(@org_admin),
      github_com_member_roles:
        [@organization.name + ":Owner", @organization2.name + ":Owner"].sort,
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [org_admin_verified_email],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: true,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: vss_user.display_login,
      github_com_name: vss_user.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: ViewModel::URLs.new.user_url(vss_user),
      github_com_member_roles: [@organization.name + ":Member"],
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: "Matched to Cloud",
      visual_studio_subscription_email: vss_user_bbla.email,
      total_user_accounts: 1
    },
    {
      github_com_login: ent_user.display_login,
      github_com_name: ent_user.profile.name,
      enterprise_server_user_ids: [
        "#{ent_inst_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Owner",
        "#{ent_inst_user_act2.remote_user_id}:#{@enterprise_installation2.host_name}:Owner"
      ].sort,
      github_com_user: true,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(ent_user),
      github_com_member_roles: [@organization.name + ":Billing manager"],
      github_com_enterprise_roles: ["Member", "Pending invitation"],
      github_com_verified_domain_emails: [ent_user_email],
      github_com_saml_name_id: ent_user_nameid,
      github_com_orgs_with_pending_invites: [@organization2.name],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ent_user_email].sort,
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 3
    },
    {
      github_com_login: ghes_vss_user.display_login,
      github_com_name: ghes_vss_user.profile.name,
      enterprise_server_user_ids: ["#{ghes_vss_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: true,
      enterprise_server_user: true,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: ViewModel::URLs.new.user_url(ghes_vss_user),
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [ghes_vss_user_email],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_vss_user_email],
      visual_studio_license_status: "Matched to Cloud + Server",
      visual_studio_subscription_email: ghes_vss_user_email,
      total_user_accounts: 2
    },
    {
      github_com_login: org_invited_user.display_login,
      github_com_name: org_invited_user.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(org_invited_user),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: outside_collab_user_pending.display_login,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(outside_collab_user_pending),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending outside collaborator invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: outside_collab_user_accepted.display_login,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(outside_collab_user_accepted),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Outside collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # ghes-only user with different primary email addresses on different instances
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: [
        "#{ghes_user2_act.remote_user_id}:#{@enterprise_installation.host_name}:Member",
        "#{ghes_user2_act2.remote_user_id}:#{@enterprise_installation.host_name}:Owner"
      ].sort,
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_user2_email, ghes_user2_email2].sort,
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 2
    },
    { # ghes-only user with a primary email
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: ["#{ghes_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_user_email],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # org invite by email without a corresponding user
      github_com_login: org_invite_email,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 0
    },
    { # ghes-only user without a primary email
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: ["#{noemail_ghes.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # org invite by email using an allocated VSS license
      github_com_login: "vss-org@invite.com",
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: "Pending Invitation",
      visual_studio_subscription_email: "vss-org@invite.com",
      total_user_accounts: 0,
    }]

    expected_hash_page_beyond_last_page = []

    assert_equal 12, hash_page_less_than_0[:total_seats_consumed]
    assert_equal 12, hash_page_less_than_0[:users].size
    assert_equal 12, hash_page_beyond_last_page[:total_seats_consumed]
    assert_equal 0, hash_page_beyond_last_page[:users].size

    0..expected_full_hash.size.times do |i|
      assert_equal expected_full_hash[i], hash_page_less_than_0[:users][i]
    end

    assert_equal expected_hash_page_beyond_last_page, hash_page_beyond_last_page[:users]
  end

  test "returns a hash for all types of users in business with pagination" do
    create(:enterprise_agreement, :visual_studio_bundle, business: @business)

    verified_org_domain = create(:verifiable_domain, owner: @organization, domain: "example.com", verified: true)
    verified_bus_domain = create(:verifiable_domain, owner: @business, domain: "xyz.lol", verified: true)

    # Org admin - tweak profile and verify email
    create(:profile, name: "Org Admin", user: @org_admin)
    org_admin_verified_email = "org-admin@xyz.lol"
    @org_admin.add_email(org_admin_verified_email).verify!

    # VSS user
    vss_user = create(:user, login: "vss-user")
    create(:profile, name: "VSS User", user: vss_user)
    @organization.add_member(vss_user)
    vss_user_bbla = create(:licensing_bundled_license_assignment, user: vss_user, business: @business)

    # Enterprise user that has everything:
    # - a SAML NameID,
    # - a verified org-level domain email,
    # - is a GHES user on multiple instances, with multiple emails on one instance,
    # - is the org's billing manager
    # - a pending org invite
    ent_user = create(:user, login: "ent-user")
    create(:profile, name: "Enterprise User", user: ent_user)
    ent_user_email = "ent-user@example.com"
    ent_user_ano_email = "ent-user@another.com"
    ent_user.add_email(ent_user_email).verify!
    @organization.add_member(ent_user)
    @organization2.invite(ent_user, inviter: @org_admin)
    Organization::BillingManagement.new(@organization).add_manager(ent_user, actor: @org_admin)
    provider = create :organization_saml_provider, organization: @organization
    ent_user_nameid = "ent-user-NameID"
    saml_user_data = Platform::Provisioning::SamlUserData.new([
      { "name" => "NameID", "value" => ent_user_nameid },
    ])
    create(:external_identity, provider: provider, user: ent_user, saml_user_data: saml_user_data)

    ent_inst_user_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation,
      site_admin: true,
      business_user_account: ent_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act,
      email: ent_user_email, primary: true

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act,
      email: ent_user_ano_email, primary: false

    ent_inst_user_act2 = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      site_admin: true,
      business_user_account: ent_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ent_inst_user_act2,
      email: "ent-user@example.com", primary: true

    # GHES-only user with a primary email
    ghes_user_email = "ghes-user@example.com"
    ghes_user_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user_act,
      email: ghes_user_email, primary: true

    create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user_act],
      login: ghes_user_email, roles: [:server_member]

    # GHES-only user without a primary email
    noemail_ghes = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation

    create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [noemail_ghes],
      login: "user-#{noemail_ghes.remote_user_id}", roles: [:server_member]

    # GHES-only user with different primary email addresses on different instances
    ghes_user2_email = "ghes-user2@example.com"
    ghes_user2_email2 = "a-ghes-user2@example.com"
    ghes_user2_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation,
      login: "a-ghes-user2"

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act,
      email: ghes_user2_email, primary: true

    ghes_user2_bus_act = create :business_user_account, business: @business, user: nil,
      enterprise_installation_user_accounts: [ghes_user2_act],
      login: ghes_user2_email, roles: [:server_member]

    ghes_user2_act2 =  create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation2,
      site_admin: true,
      business_user_account: ghes_user2_bus_act,
      login: "a-ghes-user2-site-admin"

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_user2_act2,
      email: ghes_user2_email2, primary: true

    # GHES user which matches a VSS user
    ghes_vss_user_email = "ghes-vss@example.com"
    ghes_vss_user = create(:user, login: "ghes-vss-user", email: ghes_vss_user_email)
    create(:profile, name: "GHES VSS User", user: ghes_vss_user)
    @business.add_user_accounts([ghes_vss_user.id])
    ghes_vss_user_bbla = create :licensing_bundled_license_assignment,
      user: ghes_vss_user, email: ghes_vss_user_email, business: @business

    ghes_vss_user_act = create :enterprise_installation_user_account,
      enterprise_installation: @enterprise_installation,
      business_user_account: ghes_vss_user.business_user_accounts.first

    create :enterprise_installation_user_account_email,
      enterprise_installation_user_account: ghes_vss_user_act,
      email: ghes_vss_user_email, primary: true

    # User invited to an org with pending invitation
    org_invited_user = create(:user, login: "org-invited-user")
    create(:profile, name: "Org Invited User", user: org_invited_user)
    @organization.invite(org_invited_user, inviter: @org_admin)

    # Org invite by email without a corresponding user
    org_invite_email = "test@invite.com"
    @organization.invite(email: org_invite_email, inviter: @org_admin)

    # Private org repo with pending outside collaborator user invite
    outside_collab_user_pending = create(:user, login: "outside-collab-user-pending")
    create(:repository_invitation, repository: @private_repo, invitee: outside_collab_user_pending)

    # Private org repo with accepted outside collaborator user invite
    outside_collab_user_accepted = create(:user, login: "outside-collab-user-accepted")
    create(:repository_invitation, repository: @private_repo, invitee: outside_collab_user_accepted).accept!

    # Org invite by and VSS assigned email address
    vss_org_invite_email = "vss-org@invite.com"
    @organization.invite(email: vss_org_invite_email, inviter: @org_admin)
    create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "vss-org@invite.com")

    perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob])
    @business = Business.find(@business.id)

    attributer = Business::LicenseAttributer.new(@business)
    hash_page_1 = Business::LicenseCsvUsageBuilder.new(attributer).process(pagination: true, page: 1, per_page: 6)
    hash_page_2 = Business::LicenseCsvUsageBuilder.new(attributer).process(pagination: true, page: 2, per_page: 6)

    expected_page_1 = [{
      github_com_login: @org_admin.display_login,
      github_com_name: @org_admin.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(@org_admin),
      github_com_member_roles:
        [@organization.name + ":Owner", @organization2.name + ":Owner"].sort,
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [org_admin_verified_email],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: true,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: vss_user.display_login,
      github_com_name: vss_user.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: ViewModel::URLs.new.user_url(vss_user),
      github_com_member_roles: [@organization.name + ":Member"],
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: "Matched to Cloud",
      visual_studio_subscription_email: vss_user_bbla.email,
      total_user_accounts: 1
    },
    {
      github_com_login: ent_user.display_login,
      github_com_name: ent_user.profile.name,
      enterprise_server_user_ids: [
        "#{ent_inst_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Owner",
        "#{ent_inst_user_act2.remote_user_id}:#{@enterprise_installation2.host_name}:Owner"
      ].sort,
      github_com_user: true,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(ent_user),
      github_com_member_roles: [@organization.name + ":Billing manager"],
      github_com_enterprise_roles: ["Member", "Pending invitation"],
      github_com_verified_domain_emails: [ent_user_email],
      github_com_saml_name_id: ent_user_nameid,
      github_com_orgs_with_pending_invites: [@organization2.name],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ent_user_email].sort,
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 3
    },
    {
      github_com_login: ghes_vss_user.display_login,
      github_com_name: ghes_vss_user.profile.name,
      enterprise_server_user_ids: ["#{ghes_vss_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: true,
      enterprise_server_user: true,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: ViewModel::URLs.new.user_url(ghes_vss_user),
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [ghes_vss_user_email],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_vss_user_email],
      visual_studio_license_status: "Matched to Cloud + Server",
      visual_studio_subscription_email: ghes_vss_user_email,
      total_user_accounts: 2
    },
    {
      github_com_login: org_invited_user.display_login,
      github_com_name: org_invited_user.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(org_invited_user),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: outside_collab_user_pending.display_login,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(outside_collab_user_pending),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending outside collaborator invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    }]

    expected_page_2 = [{
      github_com_login: outside_collab_user_accepted.display_login,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(outside_collab_user_accepted),
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Outside collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # ghes-only user with different primary email addresses on different instances
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: [
        "#{ghes_user2_act.remote_user_id}:#{@enterprise_installation.host_name}:Member",
        "#{ghes_user2_act2.remote_user_id}:#{@enterprise_installation.host_name}:Owner"
      ].sort,
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_user2_email, ghes_user2_email2].sort,
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 2
    },
    { # ghes-only user with a primary email
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: ["#{ghes_user_act.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [ghes_user_email],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # org invite by email without a corresponding user
      github_com_login: org_invite_email,
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 0,
    },
    { # ghes-only user without a primary email
      github_com_login: "",
      github_com_name: nil,
      enterprise_server_user_ids: ["#{noemail_ghes.remote_user_id}:#{@enterprise_installation.host_name}:Member"],
      github_com_user: false,
      enterprise_server_user: true,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: [],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    { # org invite by email using an allocated VSS license
      github_com_login: "vss-org@invite.com",
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: "Visual Studio subscription",
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Pending invitation"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [@organization.name],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: "Pending Invitation",
      visual_studio_subscription_email: "vss-org@invite.com",
      total_user_accounts: 0
    }]

    assert_equal 12, hash_page_1[:total_seats_consumed]
    assert_equal 6, hash_page_1[:users].size
    assert_equal 12, hash_page_2[:total_seats_consumed]
    assert_equal 6, hash_page_2[:users].size

    0..expected_page_1.size.times do |i|
      assert_equal expected_page_1[i], hash_page_1[:users][i]
    end
    0..expected_page_2.size.times do |i|
      assert_equal expected_page_2[i], hash_page_2[:users][i]
    end
  end

  test "returns total_seats_purchased number that includes overallocated VSS licenses" do
    business = create(:business, seats: 10)
    create(:enterprise_agreement, :visual_studio_bundle, business: business, seats: 1)
    2.times do
      create(:licensing_bundled_license_assignment, user: nil, business: business)
    end

    attributer = Business::LicenseAttributer.new(business)
    hash = Business::LicenseCsvUsageBuilder.new(attributer).process

    # 10 enterprise seats + 1 purchased VSS license + 1 overallocated VSS license
    assert_equal 12, hash[:total_seats_purchased]
  end

  context "Metered licenses enabled" do
    test "returns hash with cost center name per member" do
      @business.customer.create_billing_platform_enabled_product(copilot: true)

      member_one = create(:user)
      member_two = create(:user)
      @organization.add_member(member_one)
      @organization.add_member(member_two)

      first_cost_center = {
        costCenterKey: { customerId: @business.customer_id.to_s, targetType: :ZuoraSubscription, targetId: "", uuid: "fcb5aa21-778b-411f-90ec-2409e3713bc6" },
            name: "First Cost Center",
            resources: [
              { id: member_one.id.to_s, type: :User },
            ]
      }
      second_cost_center = {
        costCenterKey: { customerId: @business.customer_id.to_s, targetType: :ZuoraSubscription, targetId: "", uuid: "e78d46ca-2b4a-4c3f-b9e5-bc9c3db6d515" },
        name: "Second Cost Center",
        resources: [
          { id: member_two.id.to_s, type: :User }
        ]
      }
      Billing::Platform::Api::Client.any_instance
        .stubs(:get_all_cost_centers)
        .with(customer_id: @business.customer_id.to_s)
        .returns({
          costCenters: [
            first_cost_center,
            second_cost_center,
          ]
        })

      attributer = Business::LicenseAttributer.new(@business)
      hash = Business::LicenseCsvUsageBuilder.new(attributer).process

      hash[:users].each do |user|
        case user[:github_com_login]
        when member_one.login
          assert_equal first_cost_center[:name], user[:github_com_cost_center]
        when member_two.login
          assert_equal second_cost_center[:name], user[:github_com_cost_center]
        else
          assert_nil user[:github_com_cost_center]
        end
      end
    end

    test "returns hash with cost center as unavailable when api errors" do
      @business.customer.create_billing_platform_enabled_product(copilot: true)

      Billing::Platform::Api::Client.any_instance
        .stubs(:get_all_cost_centers)
        .with(customer_id: @business.customer_id.to_s)
        .returns(Billing::Platform::Api::Error.new("Test error"))

      attributer = Business::LicenseAttributer.new(@business)
      hash = Business::LicenseCsvUsageBuilder.new(attributer).process

      hash[:users].each do |user|
        assert_equal user[:github_com_cost_center], "Unavailable"
      end
    end

    test "returns hash with license tracking fields when available" do
      @business.customer.create_billing_platform_enabled_product(copilot: true)

      Billing::Platform::Api::Client.any_instance
        .stubs(:get_all_cost_centers)
        .with(customer_id: @business.customer_id.to_s)
        .returns(Billing::Platform::Api::Error.new("Test error"))

      attributer = Business::LicenseAttributer.new(@business)
      hash = Business::LicenseCsvUsageBuilder.new(attributer).process

      hash[:users].each do |user|
        assert_equal user[:github_com_cost_center], "Unavailable"
      end
    end
  end

  context "Metered licenses disabled" do
    test "returns hash without the cost center key" do
      attributer = Business::LicenseAttributer.new(@business)
      hash = Business::LicenseCsvUsageBuilder.new(attributer).process

      refute_includes hash[:users].first&.keys, :github_com_cost_center
    end

    test "returns hash without the license status keys" do
      attributer = Business::LicenseAttributer.new(@business)
      hash = Business::LicenseCsvUsageBuilder.new(attributer).process

      refute_includes hash[:users].first&.keys, :ghe_license_status
      refute_includes hash[:users].first&.keys, :ghe_license_start_date
      refute_includes hash[:users].first&.keys, :ghe_license_end_date
    end
  end

  test "returns ghas license usage of users for enterprises when enabled" do
    response = Twirp::ClientResp.new(data: ::Turboghas::Proto::GetActiveCommittersResponse.new(users: [
      ::Turboghas::Proto::GetActiveCommittersResponse::User.new(id: @org_admin.id),
    ]))

    ::Turboghas::AdvancedSecurityAPI.any_instance.stubs(:get_active_committers).returns(response)

    Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
    Business::LicenseCsvUsageBuilder.stub_const(:MAX_USER_PROFILE_QUERIES, 3) do
      user = create :user
      @organization.add_member(user)

      attributer = Business::LicenseAttributer.new(@business)
      hash = Business::LicenseCsvUsageBuilder.new(attributer).process

      assert_equal hash[:users].count, 2
      refute_nil hash[:users][0][:github_com_advanced_security_license_user]
      assert_equal hash[:users][0][:github_com_advanced_security_license_user], true
      assert_equal hash[:users][1][:github_com_advanced_security_license_user], false
    end
  end
end if GitHub.billing_enabled?

class EmuBusinessLicenseCsvUsageBuilderProcess < GitHub::TestCase
  include ExternalGroupHelpers

  fixtures do
    @owner = create(:emu, :owner)
    @business = @owner.enterprise_managed_business
    @first_admin = @business.find_first_emu_owner
    @organization = create :organization, business: @business, admin: @owner
  end

  setup do
    GitHub.flipper[:disable_external_group_team_reconcile_job].disable
  end

  test "returns a hash indicating no license usage when no users in business" do
    owner = create(:emu, :owner)
    enterprise = owner.enterprise_managed_business
    attributer = Business::LicenseAttributer.new(enterprise)
    hash = Business::LicenseCsvUsageBuilder.new(attributer).process

    assert_equal hash[:total_seats_consumed], 0
    assert_empty hash[:users]
  end

  test "returns the correct number of users for large enterprises" do
    Business::LicenseCsvUsageBuilder.stub_const(:MAX_USER_PROFILE_QUERIES, 3) do
      create_list(:emu, 10, business: @business).each { |u| @organization.add_member(u) }
      attributer = Business::LicenseAttributer.new(@business)
      hash = Business::LicenseCsvUsageBuilder.new(attributer).process

      assert_equal hash[:users].count, 11 # 10 users + 1 owner
    end
  end

  test "sets Guest Collaborator value" do
    # User with a Guest Collaborator role
    guest_collaborator_org_membership = create :emu, :guest_collaborator, login: "guest-collaborator", business: @business
    external_group = create(:external_group, :with_team, business: @business).reload
    team = external_group.external_group_teams.first.team
    perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob]) do
      team.add_member(guest_collaborator_org_membership)
      ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: guest_collaborator_org_membership.external_identities.first)
      reconcile_external_group_teams(external_group: external_group)
    end

    @business.reload
    attributer = Business::LicenseAttributer.new(@business)
    hash = Business::LicenseCsvUsageBuilder.new(attributer).process

    assert_includes hash[:users][1][:github_com_enterprise_roles], "Guest Collaborator"
  end

  test "Non-licensed EMU users see a different role & status than regular users" do
    create(:enterprise_agreement, business: @business)

    # Assignment without user
    create(:licensing_bundled_license_assignment, business: @business, user: nil, email: "variety_assignment_wo_user@example.com")

    perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
    @business = Business.find(@business.id)
    attributer = Business::LicenseAttributer.new(@business, options: { include_nonlicensed_roles: true })
    hash = Business::LicenseCsvUsageBuilder.new(attributer).process

    assert_equal 1, hash[:total_seats_consumed]
    assert_equal 3, hash[:users].size

    hash_user = hash[:users].last
    expected = {
      github_com_login: "variety_assignment_wo_user@example.com",
      github_com_name: nil,
      enterprise_server_user_ids: [],
      github_com_user: false,
      enterprise_server_user: false,
      visual_studio_subscription_user: true,
      license_type: nil,
      github_com_profile: nil,
      github_com_member_roles: [],
      github_com_enterprise_roles: ["Unlinked Visual Studio license subscription"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: nil,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: "Not a member of any enterprise organizations",
      visual_studio_subscription_email: "variety_assignment_wo_user@example.com",
      total_user_accounts: 0
    }

    assert_equal expected, hash_user
  end

  test "returns a hash for all types of users in business" do
    create(:enterprise_agreement, business: @business)

    # These should not appear anywhere in the hash
    verified_org_domain = create(:verifiable_domain, owner: @organization, domain: "example.com", verified: true)
    verified_bus_domain = create(:verifiable_domain, owner: @business, domain: "xyz.lol", verified: true)
    approved_org_domain = create(:verifiable_domain, owner: @organization, domain: "org-approved.com", approved: true)
    approved_bus_domain = create(:verifiable_domain, owner: @business, domain: "bus-approved.com", approved: true)

    # this normal EMU should consume a license because it's an explicit org member (directly added)
    member = create :emu, login: "member", business: @business
    @organization.add_member(member)

    team = create :team, organization: @organization
    external_group = create :external_group, :with_members, business: @business, number_of_members: 0
    external_group_team = ExternalGroupTeam.create(external_group: external_group, team: team)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

    # this guest collaborator should consume a license because it's a derived org member (indirectly added)
    guest_collaborator_one = create(:emu, :guest_collaborator, business: @business)

    team.add_member(guest_collaborator_one)
    ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: guest_collaborator_one.external_identities.first)
    reconcile_external_group_teams(external_group: external_group)

    assert @organization.member? guest_collaborator_one

    # this guest collaborator should consume a license because it's an explicit org member (directly added)
    guest_collaborator_two = create :emu, :guest_collaborator, login: "restricted-user-org-membership", business: @business
    @organization.add_member(guest_collaborator_two)

    # this guest collaborator won't show up because it shouldn't consume a license since it has no org memberships
    guest_collaborator_three = create :emu, :guest_collaborator, login: "restricted-user-no-membership", business: @business

    perform_enqueued_jobs(only: BusinessUpdateLicenseUsageJob)
    @business = Business.find(@business.id)
    attributer = Business::LicenseAttributer.new(@business)
    hash = Business::LicenseCsvUsageBuilder.new(attributer).process

    assert_equal 4, hash[:total_seats_consumed]
    assert_equal 4, hash[:users].size

    expected = [{
      github_com_login: @owner.display_login,
      github_com_name: @owner.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(@owner),
      github_com_member_roles: @owner.organizations.map { |org| "#{org.name}:Owner" },
      github_com_enterprise_roles: %w[Owner Member],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: member.display_login,
      github_com_name: member.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(member),
      github_com_member_roles: ["#{@organization.name}:Member"],
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: guest_collaborator_one.display_login,
      github_com_name: guest_collaborator_one.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(guest_collaborator_one),
      github_com_member_roles: guest_collaborator_one.organizations.map { |org| "#{org.name}:Member" },
      github_com_enterprise_roles: ["Member", "Guest Collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: guest_collaborator_two.display_login,
      github_com_name: guest_collaborator_two.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(guest_collaborator_two),
      github_com_member_roles: guest_collaborator_two.organizations.map { |org| "#{org.name}:Member" },
      github_com_enterprise_roles: ["Member", "Guest Collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      github_com_two_factor_auth_required_by_date: nil,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    }]

    0..expected.size.times do |i|
      assert_equal T.must(expected[i])[:github_com_login], hash[:users][i][:github_com_login]
      assert_equal T.must(expected[i])[:github_com_name], hash[:users][i][:github_com_name]
      assert_equal T.must(expected[i])[:enterprise_server_user_ids], hash[:users][i][:enterprise_server_user_ids]
      assert_equal T.must(expected[i])[:github_com_user], hash[:users][i][:github_com_user]
      assert_equal T.must(expected[i])[:enterprise_server_user], hash[:users][i][:enterprise_server_user]
      assert_equal T.must(expected[i])[:license_type], hash[:users][i][:license_type]
      assert_equal T.must(expected[i])[:github_com_profile], hash[:users][i][:github_com_profile]
      assert_same_elements T.must(expected[i])[:github_com_member_roles], hash[:users][i][:github_com_member_roles]
      assert_equal T.must(expected[i])[:github_com_enterprise_roles], hash[:users][i][:github_com_enterprise_roles]
      assert_equal T.must(expected[i])[:enterprise_server_user_ids], hash[:users][i][:enterprise_server_user_ids]
      assert_nil T.must(expected[i])[:github_com_saml_name_id], hash[:users][i][:github_com_saml_name_id]
      assert_equal T.must(expected[i])[:github_com_orgs_with_pending_invites], hash[:users][i][:github_com_orgs_with_pending_invites]
      assert_equal T.must(expected[i])[:github_com_two_factor_auth], hash[:users][i][:github_com_two_factor_auth]
      assert_equal T.must(expected[i])[:enterprise_server_primary_emails], hash[:users][i][:enterprise_server_primary_emails]
      assert_nil T.must(expected[i])[:visual_studio_license_status], hash[:users][i][:visual_studio_license_status]
      assert_nil T.must(expected[i])[:visual_studio_subscription_email], hash[:users][i][:visual_studio_subscription_email]
      assert_equal T.must(expected[i])[:total_user_accounts], hash[:users][i][:total_user_accounts]
    end
  end

  test "returns a hash for all types of users in business with pagination" do
    create(:enterprise_agreement, business: @business)

    # These should not appear anywhere in the hash
    verified_org_domain = create(:verifiable_domain, owner: @organization, domain: "example.com", verified: true)
    verified_bus_domain = create(:verifiable_domain, owner: @business, domain: "xyz.lol", verified: true)
    approved_org_domain = create(:verifiable_domain, owner: @organization, domain: "org-approved.com", approved: true)
    approved_bus_domain = create(:verifiable_domain, owner: @business, domain: "bus-approved.com", approved: true)

    # this normal EMU should consume a license because it's an explicit org member (directly added)
    member = create :emu, login: "member", business: @business
    @organization.add_member(member)

    team = create :team, organization: @organization
    external_group = create :external_group, :with_members, business: @business, number_of_members: 0
    external_group_team = ExternalGroupTeam.create(external_group: external_group, team: team)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

    # this guest collaborator should consume a license because it's a derived org member (indirectly added)
    guest_collaborator_one = create(:emu, :guest_collaborator, business: @business)

    team.add_member(guest_collaborator_one)
    ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: guest_collaborator_one.external_identities.first)
    reconcile_external_group_teams(external_group: external_group)

    assert @organization.member? guest_collaborator_one

    # this guest collaborator should consume a license because it's an external group member with explicit org membership (directly added alongside external group team membership)
    guest_collaborator_two = create :emu, :guest_collaborator, login: "restricted-user-org-membership", business: @business
    team.add_member(guest_collaborator_two)
    ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: guest_collaborator_two.external_identities.first)
    reconcile_external_group_teams(external_group: external_group)
    @organization.add_member(guest_collaborator_two)

    # this guest collaborator won't show up because it shouldn't consume a license since it has no org memberships
    guest_collaborator_three = create :emu, :guest_collaborator, login: "restricted-user-no-membership", business: @business

    perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob])
    @business = Business.find(@business.id)

    attributer = Business::LicenseAttributer.new(@business)
    hash_page_1 = Business::LicenseCsvUsageBuilder.new(attributer).process(pagination: true, page: 1, per_page: 3)
    hash_page_2 = Business::LicenseCsvUsageBuilder.new(attributer).process(pagination: true, page: 2, per_page: 3)

    assert_equal 4, hash_page_1[:total_seats_consumed]
    assert_equal 3, hash_page_1[:users].size
    assert_equal 4, hash_page_2[:total_seats_consumed]
    assert_equal 1, hash_page_2[:users].size

    expected_page_1 = [{
      github_com_login: @owner.display_login,
      github_com_name: @owner.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(@owner),
      github_com_member_roles: @owner.organizations.map { |org| "#{org.name}:Owner" },
      github_com_enterprise_roles: %w[Owner Member],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: member.display_login,
      github_com_name: member.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(member),
      github_com_member_roles: ["#{@organization.name}:Member"],
      github_com_enterprise_roles: ["Member"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    },
    {
      github_com_login: guest_collaborator_one.display_login,
      github_com_name: guest_collaborator_one.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(guest_collaborator_one),
      github_com_member_roles: guest_collaborator_one.organizations.map { |org| "#{org.name}:Member" },
      github_com_enterprise_roles: ["Member", "Guest Collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    }]

    expected_page_2 = [{
      github_com_login: guest_collaborator_two.display_login,
      github_com_name: guest_collaborator_two.profile.name,
      enterprise_server_user_ids: [],
      github_com_user: true,
      enterprise_server_user: false,
      visual_studio_subscription_user: false,
      license_type: "Enterprise",
      github_com_profile: ViewModel::URLs.new.user_url(guest_collaborator_two),
      github_com_member_roles: guest_collaborator_two.organizations.map { |org| "#{org.name}:Member" },
      github_com_enterprise_roles: ["Member", "Guest Collaborator"],
      github_com_verified_domain_emails: [],
      github_com_saml_name_id: nil,
      github_com_orgs_with_pending_invites: [],
      github_com_two_factor_auth: false,
      enterprise_server_primary_emails: [],
      visual_studio_license_status: nil,
      visual_studio_subscription_email: nil,
      total_user_accounts: 1
    }]

    0..expected_page_1.size.times do |i|
      assert_equal T.must(expected_page_1[i])[:github_com_login], hash_page_1[:users][i][:github_com_login]
      assert_equal T.must(expected_page_1[i])[:github_com_name], hash_page_1[:users][i][:github_com_name]
      assert_equal T.must(expected_page_1[i])[:enterprise_server_user_ids], hash_page_1[:users][i][:enterprise_server_user_ids]
      assert_equal T.must(expected_page_1[i])[:github_com_user], hash_page_1[:users][i][:github_com_user]
      assert_equal T.must(expected_page_1[i])[:enterprise_server_user], hash_page_1[:users][i][:enterprise_server_user]
      assert_equal T.must(expected_page_1[i])[:license_type], hash_page_1[:users][i][:license_type]
      assert_equal T.must(expected_page_1[i])[:github_com_profile], hash_page_1[:users][i][:github_com_profile]
      assert_same_elements T.must(expected_page_1[i])[:github_com_member_roles], hash_page_1[:users][i][:github_com_member_roles]
      assert_equal T.must(expected_page_1[i])[:github_com_enterprise_roles], hash_page_1[:users][i][:github_com_enterprise_roles]
      assert_equal T.must(expected_page_1[i])[:enterprise_server_user_ids], hash_page_1[:users][i][:enterprise_server_user_ids]
      assert_nil T.must(expected_page_1[i])[:github_com_saml_name_id], hash_page_1[:users][i][:github_com_saml_name_id]
      assert_equal T.must(expected_page_1[i])[:github_com_orgs_with_pending_invites], hash_page_1[:users][i][:github_com_orgs_with_pending_invites]
      assert_equal T.must(expected_page_1[i])[:github_com_two_factor_auth], hash_page_1[:users][i][:github_com_two_factor_auth]
      assert_equal T.must(expected_page_1[i])[:enterprise_server_primary_emails], hash_page_1[:users][i][:enterprise_server_primary_emails]
      assert_nil T.must(expected_page_1[i])[:visual_studio_license_status], hash_page_1[:users][i][:visual_studio_license_status]
      assert_nil T.must(expected_page_1[i])[:visual_studio_subscription_email], hash_page_1[:users][i][:visual_studio_subscription_email]
      assert_equal T.must(expected_page_1[i])[:total_user_accounts], hash_page_1[:users][i][:total_user_accounts]
    end

    0..expected_page_2.size.times do |i|
      assert_equal T.must(expected_page_2[i])[:github_com_login], hash_page_2[:users][i][:github_com_login]
      assert_equal T.must(expected_page_2[i])[:github_com_name], hash_page_2[:users][i][:github_com_name]
      assert_equal T.must(expected_page_2[i])[:enterprise_server_user_ids], hash_page_2[:users][i][:enterprise_server_user_ids]
      assert_equal T.must(expected_page_2[i])[:github_com_user], hash_page_2[:users][i][:github_com_user]
      assert_equal T.must(expected_page_2[i])[:enterprise_server_user], hash_page_2[:users][i][:enterprise_server_user]
      assert_equal T.must(expected_page_2[i])[:license_type], hash_page_2[:users][i][:license_type]
      assert_equal T.must(expected_page_2[i])[:github_com_profile], hash_page_2[:users][i][:github_com_profile]
      assert_same_elements T.must(expected_page_2[i])[:github_com_member_roles], hash_page_2[:users][i][:github_com_member_roles]
      assert_equal T.must(expected_page_2[i])[:github_com_enterprise_roles], hash_page_2[:users][i][:github_com_enterprise_roles]
      assert_equal T.must(expected_page_2[i])[:enterprise_server_user_ids], hash_page_2[:users][i][:enterprise_server_user_ids]
      assert_nil T.must(expected_page_2[i])[:github_com_saml_name_id], hash_page_2[:users][i][:github_com_saml_name_id]
      assert_equal T.must(expected_page_2[i])[:github_com_orgs_with_pending_invites], hash_page_2[:users][i][:github_com_orgs_with_pending_invites]
      assert_equal T.must(expected_page_2[i])[:github_com_two_factor_auth], hash_page_2[:users][i][:github_com_two_factor_auth]
      assert_equal T.must(expected_page_2[i])[:enterprise_server_primary_emails], hash_page_2[:users][i][:enterprise_server_primary_emails]
      assert_nil T.must(expected_page_2[i])[:visual_studio_license_status], hash_page_2[:users][i][:visual_studio_license_status]
      assert_nil T.must(expected_page_2[i])[:visual_studio_subscription_email], hash_page_2[:users][i][:visual_studio_subscription_email]
      assert_equal T.must(expected_page_2[i])[:total_user_accounts], hash_page_2[:users][i][:total_user_accounts]
    end
  end
end if GitHub.billing_enabled?
