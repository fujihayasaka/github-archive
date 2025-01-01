# typed: true
# frozen_string_literal: true

require "test_helper"

unless GitHub.single_business_environment?
  class BusinessUserAccountTest < GitHub::TestCase
    include AuditLog::IntegrationTestHelpers
    include DogstatsTestHelpers
    include GitHub::LoggerHelper
    include HydroTestHelpers

    fixtures do
      @site_admin = create :staff_admin_user
      @admin = create :user, login: "business-admin"
      @org1 = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @admin
      @org2 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
      @member = create :user
      @shared_member = create :user
      @org1.add_member @shared_member
      @org2.add_member @admin
      @org2.add_member @member
      @org2.add_member @shared_member
      @org2.publicize_member @shared_member

      @business = create :business, owners: [@admin]

      @admin = @business.admins.first

      @billing_message_source_uri = GlobalID.create(@business.customer).to_s
      @billing_message_entity = { customer_id: @business.customer.id, actor_id: @member.id }
    end

    def setup_user_enterprise_installations(business, member)
      perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
        business.add_organization(@org1)
        business.add_organization(@org2)
      end

      business_user_account = business.user_accounts.find_by!(user_id: member.id)

      installation = create :enterprise_installation,
        host_name: "server1.ghes.com", owner: business,
        customer_name: "Enterprise One"
      create :enterprise_installation_user_account,
             enterprise_installation: installation,
             login: member.login,
             site_admin: true,
             business_user_account: business_user_account

      installation2 = create :enterprise_installation,
        host_name: "server2.ghes.com", owner: business,
        customer_name: "Enterprise Two"
      create :enterprise_installation_user_account,
             enterprise_installation: installation2,
             login: member.login,
             business_user_account: business_user_account

      [business_user_account, installation, installation2]
    end

    context "with_business_role" do
      test "returns users with the specified role" do
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          @business.add_organization(@org1)
          @business.add_organization(@org2)
        end

        business_user_account = @business.business_user_account_for(@member)
        admin_user_account = @business.business_user_account_for(@admin)

        business_user_account.set_business_roles([:member])
        admin_user_account.set_business_roles([:owner])

        assert_same_elements [business_user_account], BusinessUserAccount.with_business_role(:member)
        assert_same_elements [admin_user_account], BusinessUserAccount.with_business_role(:owner)
      end

      test "returns users with the specified role as one of many roles" do
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          @business.add_organization(@org1)
          @business.add_organization(@org2)
        end

        business_user_account = @business.business_user_account_for(@member)
        admin_user_account = @business.business_user_account_for(@admin)

        business_user_account.set_business_roles([:member, :owner])
        admin_user_account.set_business_roles([:owner])

        assert_same_elements [business_user_account], BusinessUserAccount.with_business_role(:member)
        assert_same_elements [business_user_account, admin_user_account], BusinessUserAccount.with_business_role(:owner)
      end

      test "returns users with unaffiliated role" do
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          @business.add_organization(@org1)
          @business.add_organization(@org2)
        end

        business_user_account = @business.business_user_account_for(@member)
        admin_user_account = @business.business_user_account_for(@admin)

        business_user_account.set_business_roles([:member, :owner])
        admin_user_account.set_business_roles([:owner])

        other_user_account = create :business_user_account, business: @business, user: create(:user)
        other_user_account.set_business_roles([]) # Sets role value to 0

        assert_same_elements [other_user_account], BusinessUserAccount.with_business_role(:unaffiliated)
      end
    end

    context "add_business_role_to_accounts" do
      test "adds roles to new accounts" do
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          @business.add_organization(@org1)
          @business.add_organization(@org2)
        end

        member_bua = @business.business_user_account_for(@member)
        BusinessUserAccount.add_business_role_to_accounts(:member, [member_bua])
        member_bua.reload

        assert_same_elements [:member], member_bua.business_roles
      end

      test "adds roles to accounts with existing roles" do
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          @business.add_organization(@org1)
          @business.add_organization(@org2)
        end

        member_bua = @business.business_user_account_for(@member)
        admin_user_account = @business.business_user_account_for(@admin)
        member_bua.set_business_roles([:member])
        admin_user_account.set_business_roles([:owner])

        BusinessUserAccount.add_business_role_to_accounts(:outside_collaborator, [member_bua, admin_user_account])
        member_bua.reload
        admin_user_account.reload

        assert_same_elements [:member, :outside_collaborator], member_bua.business_roles
        assert_same_elements [:owner, :outside_collaborator], admin_user_account.business_roles
      end
    end

    context "remove_business_role_from_accounts" do
      test "removes roles from accounts with existing roles" do
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          @business.add_organization(@org1)
          @business.add_organization(@org2)
        end

        member_bua = @business.business_user_account_for(@member)
        admin_user_account = @business.business_user_account_for(@admin)

        member_bua.set_business_roles([:member, :outside_collaborator])
        admin_user_account.set_business_roles([:owner, :outside_collaborator])

        BusinessUserAccount.remove_business_role_from_accounts(:outside_collaborator, [member_bua, admin_user_account])
        member_bua.reload
        admin_user_account.reload

        assert_same_elements [:member], member_bua.business_roles
        assert_same_elements [:owner], admin_user_account.business_roles
      end

      test "does not modify roles when account does not have the role" do
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          @business.add_organization(@org1)
          @business.add_organization(@org2)
        end

        member_bua = @business.business_user_account_for(@member)
        admin_user_account = @business.business_user_account_for(@admin)

        member_bua.set_business_roles([:member])
        admin_user_account.set_business_roles([:owner])

        BusinessUserAccount.remove_business_role_from_accounts(:outside_collaborator, [member_bua, admin_user_account])
        member_bua.reload
        admin_user_account.reload

        assert_same_elements [:member], member_bua.business_roles
        assert_same_elements [:owner], admin_user_account.business_roles
      end

      test "will set accounts to unaffiliated if removing last role" do
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
          @business.add_organization(@org1)
          @business.add_organization(@org2)
        end

        member_bua = @business.business_user_account_for(@member)
        member_bua.set_business_roles([:member])

        BusinessUserAccount.remove_business_role_from_accounts(:member, [member_bua])
        member_bua.reload

        assert_same_elements [:unaffiliated], member_bua.business_roles
      end
    end

    context "licensed_users" do
      test "returns users with ghec license" do
        enterprise_user = create :business_user_account, business: @business, user: create(:user)
        visual_studio_user = create :business_user_account, business: @business, user: create(:user)
        unlicensed_user = create :business_user_account, business: @business, user: create(:user)

        enterprise_user.update!(ghec_license: :enterprise_license)
        visual_studio_user.update!(ghec_license: :vss_bundle_license)

        assert_same_elements [enterprise_user, visual_studio_user], BusinessUserAccount.licensed_users
      end

      test "chains with business scope to filter licensed users to business" do
        enterprise_user = create :business_user_account, business: @business, user: create(:user)
        other_business = create :business
        other_business_user = create :business_user_account, business: other_business, user: create(:user)

        enterprise_user.update!(ghec_license: :enterprise_license)
        other_business_user.update!(ghec_license: :vss_bundle_license)

        assert_same_elements [enterprise_user], @business.user_accounts.licensed_users
        assert_same_elements [other_business_user], other_business.user_accounts.licensed_users
        refute_includes @business.user_accounts.licensed_users, other_business_user
      end
    end

    context "validations" do
      test "require that business is present" do
        user_account = build :business_user_account, business: nil
        refute_predicate user_account, :valid?
        assert_includes user_account.errors[:business], "can't be blank"
      end

      test "require that user is unique to the business if present" do
        create :business_user_account, user: @member, business: @business
        user_account = build :business_user_account, user: @member, business: @business
        refute_predicate user_account, :valid?
        assert_includes user_account.errors[:user], "has already been taken"

        create :business_user_account, user: nil, business: @business
        user_account = build :business_user_account, user: nil, business: @business
        assert_predicate user_account, :valid?
      end
    end

    context "#name" do
      test "returns the cloud user's profile name if cloud user is available" do
        @member.update!(profile_name: Faker::Name.name)
        account = create :business_user_account, user: @member, business: @business
        create :enterprise_installation_user_account, business_user_account: account

        assert_equal @member.profile_name, account.name
      end

      test "returns the first alphabetical server user profile name if cloud user is nil" do
        account = create :business_user_account, user: nil, business: @business
        create :enterprise_installation_user_account, business_user_account: account, profile_name: "a"
        create :enterprise_installation_user_account, business_user_account: account, profile_name: "b"

        assert_equal "a", account.name
      end
    end

    context "remove_members" do
      test "removes only members with the specified ids" do
        @business.add_user_accounts(@org2.member_ids)

        assert_equal 4, @business.user_accounts.count

        @business.user_accounts.remove_members(@org2.admins.pluck(:id))
        assert_equal 3, @business.user_accounts.count
      end

      test "does not remove members from other businesses" do
        @business.add_user_accounts(@org2.member_ids)

        business2 = create :business
        business2.add_user_accounts(@org2.member_ids)
        assert_equal 5, business2.user_accounts.count

        @business.user_accounts.remove_members(@org2.admins.pluck(:id))
        assert_equal 5, business2.user_accounts.count
      end

      test "does not remove accounts that are associated with server users" do
        account = create :business_user_account, user: @member, business: @business
        create :enterprise_installation_user_account, business_user_account: account

        @business.user_accounts.remove_members(@member)
        assert_includes @business.user_accounts, account
      end
    end

    context "#orphaned" do
      test "scopes to business user accounts with no associated cloud or server users" do
        orphaned = create :business_user_account, business: @business, user: nil
        with_server_user = create :business_user_account, business: @business, user: nil
        create :enterprise_installation_user_account, business_user_account: with_server_user

        accounts = BusinessUserAccount.orphaned.to_a
        assert_includes accounts, orphaned
        refute_includes accounts, with_server_user
        refute_includes accounts, @business.user_accounts.find_by!(user: @business.owners.first)
      end
    end

    context "#update_user" do
      test "updates #login when user is updated" do
        account = create :business_user_account

        user = create :user
        account.update(user: user)
        assert_equal user.login, account.login

        user = create :user
        account.update(user_id: user.id)
        assert_equal user.login, account.login
      end

      test "stores display_login" do
        user = create(:emu)
        account = user.enterprise_managed_business.user_accounts.where(user_id: user.id).first
        assert_equal user.display_login, account.login
        if TestEnv.test_in_multitenancy_mode?
          refute_equal user.login, account.login
        else
          assert_equal user.login, account.login
        end
      end

      test "sets #login to server user primary email address when cloud user is nil" do
        account = create :business_user_account
        email = create :enterprise_installation_user_account_email, primary: true
        create :enterprise_installation_user_account, business_user_account: account, emails: [email]

        assert_equal account.user.login, account.login
        account.update(user: nil)
        assert_equal email.email, account.login
      end

      test "sets #login to server user login when cloud user is nil and there is no email" do
        account = create :business_user_account
        create :enterprise_installation_user_account, business_user_account: account, login: "user-login"

        account.update(user: nil)
        assert_equal "user-login", account.login
      end

      test "sets spammy when the user is spammy" do
        account = create :business_user_account
        refute account.spammy?

        user = create :user, spammy: true
        account.update(user: user)
        assert account.spammy?

        user = create :user
        account.update(user: user)
        refute account.spammy?
      end

      test "updates to spammy when the user is marked spammy" do
        account = create :business_user_account
        user = create :user
        account.update(user: user)
        refute account.spammy?

        user.mark_as_spammy actor: @site_admin, reason: "testing"
        assert account.reload.spammy?

        user.mark_not_spammy actor: @site_admin
        refute account.reload.spammy?
      end
    end

    context "user_enterprise_installations" do
      test "returns enterprise installations that the user is a member of" do
        business_user_account, installation, installation2 = setup_user_enterprise_installations(@business, @member)
        enterprise_installations = business_user_account.user_enterprise_installations
        assert_equal 2, enterprise_installations.size
        assert enterprise_installations.find { |enterprise_installation| enterprise_installation.host_name == installation.host_name }
        assert enterprise_installations.find { |enterprise_installation| enterprise_installation.host_name == installation2.host_name }
      end

      test "query parameter can search on host name" do
        business_user_account, installation, _ = setup_user_enterprise_installations(@business, @member)
        enterprise_installations = business_user_account.user_enterprise_installations \
          query: installation.host_name
        assert_equal 1, enterprise_installations.size
        assert_equal [installation.host_name], enterprise_installations.map(&:host_name)
      end

      test "query parameter can search on customer name" do
        business_user_account, _, installation2 = setup_user_enterprise_installations(@business, @member)
        enterprise_installations = business_user_account.user_enterprise_installations \
          query: installation2.host_name
        assert_equal 1, enterprise_installations.size
        assert_equal [installation2.customer_name], enterprise_installations.map(&:customer_name)
      end

      test "accepts an orderBy argument" do
        business_user_account, installation, installation2 = setup_user_enterprise_installations(@business, @member)
        enterprise_installations = business_user_account.user_enterprise_installations \
          order_by_field: "HOST_NAME",
          order_by_direction: "DESC"
        expected = [installation.host_name, installation2.host_name].sort { |a, b| b <=> a }
        assert_equal expected, enterprise_installations.map(&:host_name)
      end

      test "only shows installations the member is an admin of if role parameter is set to OWNER" do
        business_user_account, installation, _ = setup_user_enterprise_installations(@business, @member)
        enterprise_installations = business_user_account.user_enterprise_installations \
          role: "owner"
        assert_same_elements [installation.host_name], enterprise_installations.map(&:host_name)
      end

      test "only shows installations the member is a member (not an admin) of if role parameter is set to MEMBER" do
        business_user_account, _, installation2 = setup_user_enterprise_installations(@business, @member)
        enterprise_installations = business_user_account.user_enterprise_installations \
          role: "member"
        assert_same_elements [installation2.host_name], enterprise_installations.map(&:host_name)
      end
    end

    context "#enterprise_organizations" do
      test "it returns enterprise organizations that the user is a member of" do
        business_user_account, _, _ = setup_user_enterprise_installations(@business, @shared_member)
        enterprise_organizations = business_user_account.enterprise_organizations(@admin)
        assert_equal 2, enterprise_organizations.size
        assert enterprise_organizations.find { |org| org.login == @org1.login }
        assert enterprise_organizations.find { |org| org.login == @org2.login }
      end

      test "for admins lists all orgs (public and private membership) the member is linked through" do
        business_user_account, _, _ = setup_user_enterprise_installations(@business, @shared_member)
        enterprise_organizations = business_user_account.enterprise_organizations(@admin)
        assert_same_elements [@org1.login, @org2.login], enterprise_organizations.map(&:login)
      end

      test "for site admins lists all orgs (public and private membership) the member is linked through" do
        business_user_account, _, _ = setup_user_enterprise_installations(@business, @shared_member)
        enterprise_organizations = business_user_account.enterprise_organizations(@admin)
        assert_same_elements [@org1.login, @org2.login], enterprise_organizations.map(&:login)
      end

      test "for members lists all publicized org organizations and org membership where the member/viewer are both direct members" do
        business_user_account, _, _ = setup_user_enterprise_installations(@business, @shared_member)
        enterprise_organizations = business_user_account.enterprise_organizations(@member)
        assert_same_elements [@org2.login], enterprise_organizations.map(&:login)
      end

      test "accepts an order_by_field and order_by_direction argument" do
        business_user_account, _, _ = setup_user_enterprise_installations(@business, @shared_member)
        enterprise_organizations = business_user_account.enterprise_organizations \
          @admin,
          order_by_field: "LOGIN",
          order_by_direction: "DESC"
        expected = [@org1.login, @org2.login].sort { |a, b| b <=> a }
        assert_equal expected, enterprise_organizations.map(&:login)
      end

      test "only shows orgs the member is an admin of if org_member_type parameter is set to :admin" do
        business_user_account, _, _ = setup_user_enterprise_installations(@business, @admin)
        enterprise_organizations = business_user_account.enterprise_organizations(@admin, org_member_type: :admin)
        assert_same_elements [@org1.login], enterprise_organizations.map(&:login)
      end

      test "only shows orgs the member is a member (not admin) of if role parameter is set to :member_without_admin" do
        business_user_account, _, _ = setup_user_enterprise_installations(@business, @admin)
        enterprise_organizations = business_user_account.enterprise_organizations(@admin, org_member_type: :member_without_admin)
        assert_same_elements [@org2.login], enterprise_organizations.map(&:login)
      end
    end

    context "#enterprise_teams" do
      test "returns an empty array if no user is present" do
        business_user_account = create :business_user_account, user: nil
        assert_same_elements [], business_user_account.enterprise_teams
      end

      test "gets all of a user's teams" do
        owner = create :emu, :owner

        enterprise = owner.enterprise_managed_business

        emu_a = create :emu, business: enterprise
        emu_b = create :emu, business: enterprise

        org_a = create :organization, business: enterprise, admin: owner
        org_b = create :organization, business: enterprise, admin: owner

        team_a = create :team, organization: org_a
        team_b = create :team, organization: org_b
        team_c = create :team, organization: org_b

        team_a.add_member(emu_a)
        team_a.add_member(emu_b)
        team_b.add_member(emu_a)
        team_c.add_member(emu_b)

        assert_same_elements [team_a, team_b], emu_a.business_user_account.enterprise_teams
        assert_same_elements [team_a, team_c], emu_b.business_user_account.enterprise_teams
      end

      test "gets a user's teams by name" do
        owner = create :emu, :owner

        enterprise = owner.enterprise_managed_business

        emu = create :emu, business: enterprise

        org_a = create :organization, business: enterprise, admin: owner
        org_b = create :organization, business: enterprise, admin: owner

        team_a = create :team, organization: org_a, name: "a1230"
        team_b = create :team, organization: org_b, name: "b4560"
        team_c = create :team, organization: org_b, name: "c7890"

        team_a.add_member(emu)
        team_b.add_member(emu)
        team_c.add_member(emu)

        assert_same_elements [team_a], emu.business_user_account.enterprise_teams(query: "a")
        assert_same_elements [team_b], emu.business_user_account.enterprise_teams(query: "b")
        assert_same_elements [team_c], emu.business_user_account.enterprise_teams(query: "c")
        assert_same_elements [team_a, team_b, team_c], emu.business_user_account.enterprise_teams(query: "0")
      end

      test "orders teams by name" do
        owner = create :emu, :owner

        enterprise = owner.enterprise_managed_business

        emu = create :emu, business: enterprise

        org_a = create :organization, business: enterprise, admin: owner
        org_b = create :organization, business: enterprise, admin: owner

        team_a = create :team, organization: org_a, name: "a1230"
        team_b = create :team, organization: org_b, name: "b4560"
        team_c = create :team, organization: org_b, name: "c7890"

        team_a.add_member(emu)
        team_b.add_member(emu)
        team_c.add_member(emu)

        assert_equal "a1230", emu.business_user_account.enterprise_teams.first.name
        assert_equal "c7890", emu.business_user_account.enterprise_teams(order_by_direction: "DESC").first.name
      end
    end

    context "two_factor_authentication_enabled" do
      test "it returns same 2fa status for user and business user accounts" do
        account = create :business_user_account, user: @member, business: @business

        refute @member.two_factor_authentication_enabled?
        refute account.two_factor_authentication_enabled?

        make_two_factor_credential(@member)

        assert @member.two_factor_authentication_enabled?
        assert account.two_factor_authentication_enabled?
      end
    end

    context "destroy" do
      test "does not queue SuspendEmuAndRemoveExternalIdentityJob if user account is destroyed" do
        business_user_account = create(:business_user_account, user: @member, business: @business)
        assert_enqueued_jobs 0, only: SuspendEmuAndRemoveExternalIdentityJob do
          business_user_account.destroy
        end
      end
    end
  end

  class EmuBusinessUserAccountTest < GitHub::TestCase
    fixtures do
      @emu = create :emu
      @business = @emu.enterprise_managed_business
    end

    context "destroy" do
      test "queues SuspendEmuAndRemoveExternalIdentityJob if user account is destroyed" do
        business_user_account = BusinessUserAccount.find_by(user_id: @emu.id)
        assert_enqueued_jobs 1, only: SuspendEmuAndRemoveExternalIdentityJob do
          T.must(business_user_account).destroy
        end
      end

      test "suspends and obfuscate user if user account is destroyed" do
        business_user_account = BusinessUserAccount.find_by(user_id: @emu.id)
        perform_enqueued_jobs(only: SuspendEmuAndRemoveExternalIdentityJob) do
          T.must(business_user_account).destroy
        end

        @emu = @emu.reload
        assert_predicate @emu, :suspended?
        refute_includes @emu.login, @business.shortcode
      end
    end

  end
end
