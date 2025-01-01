# typed: true
# frozen_string_literal: true

require "test_helper"

module SCIMBusinessPeopleDependencySharedTests
  extend T::Helpers

  def test_suspended_members_loads_scim_suspended_members
    T.bind(self, GitHub::TestCase)
    suspended_members = @enterprise.suspended_members

    assert_same_elements @suspended_expected, suspended_members
  end

  def test_suspended_member_ids_loads_scim_suspended_members
    T.bind(self, GitHub::TestCase)
    suspended_member_ids = @enterprise.suspended_member_ids

    assert_same_elements @suspended_expected.map(&:id), suspended_member_ids
  end

  def test_suspended_members_orders_suspended_members_by_login_ascending_by_default
    T.bind(self, GitHub::TestCase)
    suspended_members = @enterprise.suspended_members

    assert_equal @expected_login, suspended_members.map(&:login)
  end

  def test_suspended_members_orders_suspended_members_using_ordering_arguments_when_provided
    T.bind(self, GitHub::TestCase)
    suspended_members = @enterprise.suspended_members(order_by_field: "login", order_by_direction: "desc")

    assert_equal @expected_login_desc, suspended_members.map(&:login)
  end

  def test_suspended_members_ignores_invalid_ordering_arguments
    T.bind(self, GitHub::TestCase)
    suspended_members = @enterprise.suspended_members(order_by_field: "invalid field", order_by_direction: "invalid direction")

    assert_equal @expected_login, suspended_members.map(&:login)
  end

  def test_suspended_members_queries_for_members_by_login
    T.bind(self, GitHub::TestCase)
    suspended_members = @enterprise.suspended_members(query: "suspended-user")

    assert_same_elements [@suspended1], suspended_members
  end

  def test_suspended_members_queries_for_members_by_profile
    T.bind(self, GitHub::TestCase)
    suspended_members = @enterprise.suspended_members(query: "member")

    assert_same_elements [@suspended1], suspended_members
  end
end

class BusinessPeopleDependencyTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @admin = create :user, login: "org-admin"
    @server_admin = create :user, login: "server-admin"

    # [pending] collaborators
    @collaborator1 = create :user, login: "collaborator1"
    @collaborator2 = create :user, login: "collaborator2"
    @collaborator3 = create :user, login: "other-collab"
    @pending_collaborator1 = create :user, login: "pending-collaborator1"
    @pending_collaborator2 = create :user, login: "pending-collaborator2"
    @pending_collaborator3 = create :user, login: "pending-other"

    @collaborator1.profile_name = "collab name"
    @collaborator1.save!
    @pending_collaborator1.profile_name = "pending collab name"
    @pending_collaborator1.save!

    @org1 = create :organization, admin: @admin
    @repo1 = create(:public_repository, owner: @org1)
    @repo1.add_member(@collaborator1)
    @repo1.add_member(@collaborator3)
    RepositoryInvitation.invite_to_repo(@pending_collaborator1, @admin, @repo1)
    RepositoryInvitation.invite_to_repo(@pending_collaborator3, @admin, @repo1)
    RepositoryInvitation.invite_to_repo_by_email "invitee@example.com", @admin, @repo1

    @org2 = create :organization, admin: @admin
    @repo2 = create(:private_repository, owner: @org2)
    @repo2.add_member(@collaborator2)
    RepositoryInvitation.invite_to_repo(@pending_collaborator2, @admin, @repo2)

    # [pending] members
    @member1 = create :user, login: "pending-org-member1"
    @member2 = create :user, login: "pending-org-member2"
    @member3 = create :user, login: "pending-other-member"

    @member4 = create :user, login: "orgs-member"
    @enterprise_licensed_member1 = create :user, login: "enterprise-licensed-org-member1"
    @enterprise_licensed_member2 = create :user, login: "enterprise-licensed-org-member2"
    @volume_licensed_member1 = create :user, login: "volume-licensed-member1"
    @volume_licensed_member2 = create :user, login: "server-member"
    @rando = create :user, login: "rando"

    @enterprise_licensed_member1.profile_name = "licensed member name"
    @enterprise_licensed_member1.save!

    @org1.add_member(@enterprise_licensed_member1)
    @org1.add_member(@volume_licensed_member1)
    @org1.add_member(@member4)
    @org2.add_member(@enterprise_licensed_member2)
    @org2.add_member(@member4)
    @org1.reload.add_member(User.ghost)

    @member1.profile_name = "member name"
    @member1.save!
    @member3.profile_name = "Charlie"
    @member3.save!

    @org1.invite(@member1, inviter: @admin, invitation_source: :member).update created_at: 100.minutes.ago
    @org1.invite(@member3, inviter: @admin, invitation_source: :scim).update created_at: 99.minutes.ago
    @org2.invite(@member2, inviter: @admin, invitation_source: :member).update created_at: 98.minutes.ago
    @org1.invite(nil, email: "test@org1.com.net", inviter: @org1.admins.first, invitation_source: :member).update created_at: 97.minutes.ago
    @org2.invite(nil, email: "test@org1.com.net", inviter: @org2.admins.first, invitation_source: :scim).update created_at: 96.minutes.ago
    @org2.invite(nil, email: "test@org2.com.net", inviter: @org2.admins.first, invitation_source: :unknown).update created_at: 95.minutes.ago

    # biz
    customer = create :customer, payment_method: \
      build(:paypal_payment_method, user: @rando, customer: nil)
    @business = create :business, :volume_licensed, owners: [@admin], organizations: [@org1, @org2], customer: customer

    unless GitHub.single_business_environment?
      @basic_emu = create :emu
      @basic_business = @basic_emu.enterprise_managed_business
      @basic_business.update seats_plan_type: :basic
      @basic_owner = @basic_business.owners.first
      @basic_admin = create :emu, :owner, business: @basic_business
    end

    @billing_manager = create :user, login: "billing-manager"
    @business.billing.add_manager(@billing_manager, actor: @admin)

    # [pending] bundled license assignments
    @assignment1 = create(:licensing_bundled_license_assignment, business_id: @business.id, email: "test@org1.com.net").update created_at: 94.minutes.ago
    @assignment2 = create(:licensing_bundled_license_assignment, business_id: @business.id, email: "test1@test.com.net").update created_at: 93.minutes.ago
    @assignment3 = create(:licensing_bundled_license_assignment, business_id: @business.id, email: "test2@test.com.net").update created_at: 92.minutes.ago
    @assignment4 = create(:licensing_bundled_license_assignment, business_id: @business.id, email: "test3@test.com.net").update created_at: 91.minutes.ago
    @assignment5 = create(:licensing_bundled_license_assignment, business_id: @business.id, email: "user1@test.com.net").update created_at: 90.minutes.ago
    @assignment6 = create(:licensing_bundled_license_assignment, business_id: @business.id, email: "user2@test.com.net").update created_at: 89.minutes.ago
    @assignment7 = create(:licensing_bundled_license_assignment, business_id: @business.id, user_id: @member1.id).update created_at: 88.minutes.ago

    # licenses
    @business_installation = create(:enterprise_installation, owner: @business)

    create :enterprise_installation_user_account, \
      enterprise_installation: @business_installation,
      site_admin: true,
      business_user_account: create(:business_user_account, user: @server_admin, business: @business)

    create :enterprise_installation_user_account, \
      enterprise_installation: @business_installation,
      profile_name: "herp",
      business_user_account: create(:business_user_account, user: @volume_licensed_member2, business: @business)

    if GitHub.billing_enabled?
      create :licensing_bundled_license_assignment, user: @enterprise_licensed_member1, business: @business, revoked: true
      create :licensing_bundled_license_assignment, user: @volume_licensed_member1, business: @business
      create :licensing_bundled_license_assignment, user: @volume_licensed_member2, business: @business

      # create assignments on a different business to catch regression in join logic
      random_business = create :business
      create :licensing_bundled_license_assignment, user: @enterprise_licensed_member1, business: random_business
    end

    # suspended users
    @suspended1 = create :user, login: "suspended1"
    @suspended2 = create :user, login: "suspended2"
    @suspended_other = create :user, login: "other-suspended"

    @suspended1.profile_name = "suspended member 1"
    @suspended1.save!

    @org3 = create :organization, admin: @admin, business: @business
    @org3.add_member(@suspended1)
    @org3.add_member(@suspended2)
    @org3.add_member(@suspended_other)
    @org3.add_member(@member4)

    @suspended1.suspend("test supsension")
    @suspended2.suspend("test supsension")
    @suspended_other.suspend("test supsension")

    # enterprise installations
    if !GitHub.single_business_environment?
      @second_admin = create :user, login: "business-admin"
      @second_org = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @second_admin
      @second_member = create :user
      @second_org.add_member @second_member
      @second_business = create :business, owners: [@second_admin]
    end
  end

  setup do
    BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
    BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @basic_business.id) unless GitHub.single_business_environment?
  end

  def setup_member_with_read_enterprise_admins_and_members(member)
    enable_feature_flag(:custom_enterprise_role_feature, @business)
    enable_feature_flag(:support_enterprise_admins_and_members, @business)
    grant_custom_enterprise_role(user: member, target: @business, fgps: [:read_enterprise_admins_and_members])
  end

  def setup_user_enterprise_installations(business, org, member)
    perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) do
      business.add_organization(org)
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

  def assert_members_includes(members, user, business = @business)
    if GitHub.single_business_environment?
      assert_includes members, user
    else
      assert_includes members, user.business_user_accounts.find_by!(business_id: business.id)
    end
  end

  def refute_members_includes(members, user, business = @business)
    if GitHub.single_business_environment?
      refute_includes members, user
    else
      if bua = user.business_user_accounts.find_by(business_id: business.id)
        refute_includes members, bua
      else
        refute_includes members.pluck(:user_id), user.id
      end
    end
  end

  def stub_cost_center
    @cloud_and_server_user = create :user, login: "cloud-and-server-user"
    @org1.add_member(@cloud_and_server_user)
    create :enterprise_installation_user_account, \
      enterprise_installation: @business_installation,
      business_user_account: @business.user_accounts.find_by!(user_id: @cloud_and_server_user.id)

    @server_only_bua = create(:business_user_account, user: nil, business: @business)
    create :enterprise_installation_user_account, \
      enterprise_installation: @business_installation,
      profile_name: "server-only-user",
      business_user_account: @server_only_bua

    @business.customer.create_billing_platform_enabled_product(ghec: true)
    test_cost_center = {
      costCenterKey: { customerId: @business.customer_id.to_s, targetType: :ZuoraSubscription, targetId: "", uuid: "fcb5aa21-778b-411f-90ec-2409e3713bc6" },
      name: "Test Cost Center",
      resources: [
        { id: @enterprise_licensed_member1.id.to_s, type: :User },
        { id: @volume_licensed_member1.id.to_s, type: :User },
        { id: @cloud_and_server_user.id.to_s, type: :User },
        { id: @server_admin.id.to_s, type: :User },
      ]
    }
    empty_cost_center = {
      costCenterKey: { customerId: @business.customer_id.to_s, targetType: :ZuoraSubscription, targetId: "", uuid: "01927c94-07b1-7e0f-9a1f-7cfcf2327ec8" },
      name: "Empty Cost Center",
      resources: []
    }

    Billing::Platform::Api::Client.any_instance
      .stubs(:get_all_cost_centers)
      .with(customer_id: @business.customer_id.to_s, use_cache: true)
      .returns({ costCenters: [
        test_cost_center,
        empty_cost_center
      ] })
    BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
  end

  context "#filtered_members" do
    test "loads all members by default" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer)

        if GitHub.single_business_environment?
          assert_equal 18, members.count
          assert_members_includes members, @rando
        else
          assert_equal 11, members.count
          assert_members_includes members, @suspended1
          assert_members_includes members, @suspended2
          assert_members_includes members, @suspended_other
        end

        assert_members_includes members, @admin
        assert_members_includes members, @billing_manager
        assert_members_includes members, @enterprise_licensed_member1
        assert_members_includes members, @enterprise_licensed_member2
        assert_members_includes members, @volume_licensed_member1
        assert_members_includes members, @volume_licensed_member2
        assert_members_includes members, @server_admin
        assert_members_includes members, @member4
      end
    end

    test "loads results for enterprise members when no filters are specified" do
      viewer = @member4
      bua_filtered = [viewer, @business].any? { |actor| actor.feature_enabled?(:business_user_account_filtered_members, memoize: false) }

      expected_members = [
        @admin,
        (@server_admin unless GitHub.enterprise? || bua_filtered),
        @enterprise_licensed_member1,
        @enterprise_licensed_member2,
        @volume_licensed_member1,
        (@volume_licensed_member2 unless GitHub.enterprise? || bua_filtered),
        (@suspended1 unless GitHub.enterprise?),
        (@suspended2 unless GitHub.enterprise?),
        (@suspended_other unless GitHub.enterprise?),
        @member4,
      ].compact_blank!

      members = @business.filtered_members(viewer)
      expected_members.each { |m| assert_members_includes members, m }
      assert_equal expected_members.count, members.count
    end

    unless GitHub.single_business_environment?
      test "loads all members for basic business member" do
        members = @basic_business.filtered_members(@basic_emu)
        assert_equal 2, members.count
        assert_members_includes members, @basic_emu, @basic_business
        assert_members_includes members, @basic_admin, @basic_business
      end
    end

    test "includes spammy members" do
      spammer = create :user, spammy: true
      @org1.add_member(spammer)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer)
        if GitHub.single_business_environment?
          assert_equal 19, members.count
          assert_members_includes members, @rando
        else
          assert_equal 12, members.count
          assert_members_includes members, @suspended1
          assert_members_includes members, @suspended2
          assert_members_includes members, @suspended_other
        end

        assert_members_includes members, @admin
        assert_members_includes members, @billing_manager
        assert_members_includes members, @enterprise_licensed_member1
        assert_members_includes members, @enterprise_licensed_member2
        assert_members_includes members, @volume_licensed_member1
        assert_members_includes members, @volume_licensed_member2
        assert_members_includes members, @server_admin
        assert_members_includes members, @member4
        assert_members_includes members, spammer
      end
    end

    unless GitHub.single_business_environment?
      test "includes admins not in organization" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer)
          expected = %w[
            billing-manager
            enterprise-licensed-org-member1
            enterprise-licensed-org-member2
            org-admin
            orgs-member
            other-suspended
            server-admin
            server-member
            suspended1
            suspended2
            volume-licensed-member1
          ]
          assert_equal expected, members.paginate(page: 1).map(&:login)
        end
      end

      test "filters by enterprise owner role" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, role: "enterprise_owner")
          assert_equal 1, members.count
          assert_members_includes members, @admin
        end
      end

      unless GitHub.single_business_environment?
        test "filters by enterprise owner role for basic business member" do
          members = @basic_business.filtered_members(@basic_emu, role: "enterprise_owner")
          assert_equal 2, members.count
          assert_members_includes members, @basic_owner, @basic_business
          assert_members_includes members, @basic_admin, @basic_business
        end
      end

      test "filters by billing manager role" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, role: "billing_manager")
          assert_equal 1, members.count
          assert_members_includes members, @billing_manager
        end
      end

      unless GitHub.single_business_environment?
        test "returns no results when trying to filter by billing manager role for basic business member" do
          members = @basic_business.filtered_members(@basic_emu, role: "billing_manager")
          assert_equal 0, members.count
        end
      end

      test "includes admins consuming license when license filter is passed" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, license: "enterprise")
          refute_members_includes members, @billing_manager
          assert_members_includes members, @admin
        end
      end

      test "includes admins consuming license when license and enterprise owner role filter is passed" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, license: "enterprise", role: "enterprise_owner")
          assert_equal 1, members.count
          refute_members_includes members, @billing_manager
          assert_members_includes members, @admin
        end
      end

      test "return empty when license and billing manager role filter is passed" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, license: "enterprise", role: "billing_manager")
          assert_empty members
        end
      end

      test "return empty when org login does not have any members with enterprise owner role" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, organization_logins: [@org1.login], role: "enterprise_owner")
          assert_equal 1, members.count
          assert_members_includes members, @admin
        end
      end

      test "return empty when org login does not have any members with billing manager role" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, organization_logins: [@org1.login], role: "billing_manager")
          assert_empty members
        end
      end

      test "does not include admins without org membership when org login is passed" do
        new_org = create :organization, login: "new-org", business: @business
        new_org.add_member(@enterprise_licensed_member2)
        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, organization_logins: [new_org.login])
          assert_empty members
        end
      end

      test "filters to members of server deployments with enterprise owner role" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          @business.add_owner(@server_admin, actor: @admin)
          BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
          members = @business.filtered_members(viewer, deployment: "server", role: "enterprise_owner")
          assert_equal 1, members.count
          assert_members_includes members, @server_admin
        end
      end

      test "filters to members of GHEC with enterprise owner role" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, deployment: "cloud", role: "enterprise_owner")
          assert_equal 1, members.count
          assert_members_includes members, @admin
        end
      end

      test "does not include admins without org membership when org member role is passed" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, role: "member")
          refute_members_includes members, @admin
          refute_members_includes members, @billing_manager
          assert_members_includes members, @enterprise_licensed_member1
          assert_members_includes members, @enterprise_licensed_member2
          assert_members_includes members, @volume_licensed_member1
          assert_members_includes members, @suspended1
          assert_members_includes members, @suspended2
          assert_members_includes members, @suspended_other
        end
      end

      test "does not include admins without org ownership when org owner role is passed" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, role: "owner")
          assert_equal 2, members.count
          assert_members_includes members, @server_admin
          assert_members_includes members, @admin
        end
      end

      test "does not include admins when viewer is not an owner" do
        members = @business.filtered_members(@member)
        refute_members_includes members, @billing_manager
        refute_members_includes members, @admin
      end

      unless GitHub.single_business_environment?
        test "does include admins when viewer is not an owner of basic business" do
          members = @basic_business.filtered_members(@basic_emu)
          refute_members_includes members, @basic_owner, @basic_business
          assert_members_includes members, @basic_admin, @basic_business
        end
      end
    end

    test "orders members by login ascending by default" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, batch_size: 5)
        if GitHub.single_business_environment?
          expected = %w[
            billing-manager
            collaborator1
            collaborator2
            enterprise-licensed-org-member1
            enterprise-licensed-org-member2
            org-admin
            orgs-member
            other-collab
            pending-collaborator1
            pending-collaborator2
            pending-org-member1
            pending-org-member2
            pending-other
            pending-other-member
            rando
            server-admin
            server-member
            volume-licensed-member1
          ]
        else
          expected = %w[
            billing-manager
            enterprise-licensed-org-member1
            enterprise-licensed-org-member2
            org-admin
            orgs-member
            other-suspended
            server-admin
            server-member
            suspended1
            suspended2
            volume-licensed-member1
          ]
        end
        assert_equal expected, members.paginate(page: 1).map(&:login)
      end
    end

    test "orders members using ordering arguments when provided" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, order_by_field: "login", order_by_direction: "desc", batch_size: 5)
        if GitHub.single_business_environment?
          expected = %w[
            volume-licensed-member1
            server-member
            server-admin
            rando
            pending-other-member
            pending-other
            pending-org-member2
            pending-org-member1
            pending-collaborator2
            pending-collaborator1
            other-collab
            orgs-member
            org-admin
            enterprise-licensed-org-member2
            enterprise-licensed-org-member1
            collaborator2
            collaborator1
            billing-manager
          ]
        else
          expected = %w[
            volume-licensed-member1
            suspended2
            suspended1
            server-member
            server-admin
            other-suspended
            orgs-member
            org-admin
            enterprise-licensed-org-member2
            enterprise-licensed-org-member1
            billing-manager
          ]
        end
        assert_equal expected, members.paginate(page: 1).map(&:login)
      end
    end

    unless GitHub.single_business_environment?
      test "ordered and paginated members with batched_scope" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, batched_scope: true, batch_size: 5)
          expected = %w[
            billing-manager
            enterprise-licensed-org-member1
            enterprise-licensed-org-member2
            org-admin
            orgs-member
            other-suspended
            server-admin
            server-member
            suspended1
            suspended2
            volume-licensed-member1
          ]
          assert_equal expected.slice(0, 5), members.paginate(page: 1, per_page: 5).map(&:login)
          assert_equal expected.slice(5, 5), members.paginate(page: 2, per_page: 5).map(&:login)
        end
      end
    end


    test "ignores invalid ordering arguments" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(
          viewer,
          order_by_field: "invalid field",
          order_by_direction: "invalid direction"
        )
        if GitHub.single_business_environment?
          expected = %w[
            billing-manager
            collaborator1
            collaborator2
            enterprise-licensed-org-member1
            enterprise-licensed-org-member2
            org-admin
            orgs-member
            other-collab
            pending-collaborator1
            pending-collaborator2
            pending-org-member1
            pending-org-member2
            pending-other
            pending-other-member
            rando
            server-admin
            server-member
            volume-licensed-member1
          ]
        else
          expected = %w[
            billing-manager
            enterprise-licensed-org-member1
            enterprise-licensed-org-member2
            org-admin
            orgs-member
            other-suspended
            server-admin
            server-member
            suspended1
            suspended2
            volume-licensed-member1
          ]
        end
        assert_equal expected, members.paginate(page: 1).map(&:login)
      end
    end

    test "only returns visible org memberships to non-admins by default" do
      org2_member = create :user, login: "org2-member"
      perform_enqueued_jobs only: [BusinessUserAccountCreateForOrganizationJob] do
        @org2.add_member org2_member
      end
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
      members = @business.filtered_members(org2_member)
      assert_members_includes members, @admin
      assert_members_includes members, @enterprise_licensed_member2
      assert_members_includes members, org2_member
      refute_members_includes members, @enterprise_licensed_member1
      refute_members_includes members, @volume_licensed_member1
    end

    test "ignores org membership visibility when ignore_org_membership_visibility: true" do
      org2_member = create :user, login: "org2-member"
      @org2.add_member org2_member
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

      members = @business.filtered_members(org2_member, ignore_org_membership_visibility: true)
      assert_members_includes members, @admin
      assert_members_includes members, @enterprise_licensed_member1
      assert_members_includes members, @enterprise_licensed_member2
      assert_members_includes members, @volume_licensed_member1
      assert_members_includes members, org2_member
    end

    test "excludes the ghost user" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer)

        if GitHub.single_business_environment?
          assert_equal 18, members.count
          assert_members_includes members, @rando
        else
          assert_equal 11, members.count
          assert_members_includes members, @suspended1
          assert_members_includes members, @suspended2
          assert_members_includes members, @suspended_other
        end

        assert_members_includes members, @billing_manager
        assert_members_includes members, @admin
        assert_members_includes members, @server_admin
        assert_members_includes members, @enterprise_licensed_member1
        assert_members_includes members, @enterprise_licensed_member2
        assert_members_includes members, @volume_licensed_member1
        assert_members_includes members, @volume_licensed_member2
        assert_members_includes members, @member4
        refute_members_includes members, User.ghost
      end
    end

    test "returns visible org members for subset of orgs specified in organization_logins" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, organization_logins: [@org1.login])
        assert_equal 4, members.count
        assert_members_includes members, @admin
        assert_members_includes members, @enterprise_licensed_member1
        assert_members_includes members, @volume_licensed_member1
        assert_members_includes members, @member4
      end
    end

    test "returns no members for non-existent orgs specified in organization_logins" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, organization_logins: [@org1.login + "foo"])
        assert_empty members
      end
    end

    test "queries for members by login" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, query: "org-member")

        if GitHub.single_business_environment?
          # pending organization members included on GHES
          assert_equal 4, members.count
        else
          assert_equal 2, members.count
        end

        assert_members_includes members, @enterprise_licensed_member1
        assert_members_includes members, @enterprise_licensed_member2

        members = @business.filtered_members(@admin, query: "org-member1")

        if GitHub.single_business_environment?
          assert_equal 2, members.count
        else
          assert_equal 1, members.count
        end

        assert_members_includes members, @enterprise_licensed_member1
      end
    end

    test "queries for members by profile name" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, query: "licensed member name")
        assert_equal 1, members.count
        assert_members_includes members, @enterprise_licensed_member1
      end
    end

    test "queries for members by email as owner" do

      user = create(:user, :verified, email: "test@example.com")
      create(:user_email, user: user, email: "test2@example.com")
      @org1.add_member(user)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, query: "test@example.com")
        assert_equal 1, members.count
        assert_members_includes members, user
      end
    end

    test "finds members by email as site admin with ignore_org_membership_visibility true" do
      site_admin = create :staff_admin_user
      user = create(:user, :verified, email: "test@example.com")
      create(:user_email, user: user, email: "test2@example.com")
      @org1.add_member(user)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
      members = @business.filtered_members \
        site_admin,
        query: "test@example.com",
        ignore_org_membership_visibility: true
      assert_equal 1, members.count
      assert_members_includes members, user
    end

    if GitHub.enterprise?
      test "finds members by email as site admin by default in enterprise mode" do
        site_admin = create :staff_admin_user
        user = create(:user, :verified, email: "test@example.com")
        @org1.add_member(user)
        members = @business.filtered_members site_admin, query: "test@example.com"
        assert_equal 1, members.count
        assert_members_includes members, user
      end
    else
      test "does not find members by email as site admin with by default in dotcom mode" do
        site_admin = create :staff_admin_user
        user = create(:user, :verified, email: "test@example.com")
        @org1.add_member(user)
        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
        members = @business.filtered_members site_admin, query: "test@example.com"
        assert_equal 0, members.count
      end
    end

    test "queries for members by email containing underscore as owner" do
      user = create(:user, :verified, email: "what_ever@example.com")
      @org1.add_member(user)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, query: "what_ever@example.com")
        assert_equal 1, members.count
        assert_members_includes members, user
      end
    end

    test "queries for members by unverified email as owner" do
      user = create(:user, :verified, email: "test@example.com")
      create(:user_email, user: user, email: "test2@example.com")
      @org1.add_member(user)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
      members = @business.filtered_members(@enterprise_licensed_member1, query: "test2@example.com")
      assert_equal 0, members.count
    end

    test "queries for members by external identity as owner" do
      provider = create :business_saml_provider, business: @business
      user = create(:user)
      saml_user_data = Platform::Provisioning::SamlUserData.new([
        { "name" => "NameID", "value" => "test@example.com" },
        { "name" => "emails", "value" => "test2@example.com" }
      ])
      create(:external_identity, provider: provider, user: user, saml_user_data: saml_user_data)
      @org1.add_member(user)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, query: "test@example.com")
        assert_equal 1, members.count
        assert_members_includes members, user
        members = @business.filtered_members(viewer, query: "test2@example.com")
        assert_equal 1, members.count
        assert_members_includes members, user
      end
    end

    test "does not find results when querying for members by email as user" do
      user = create(:user, :verified, email: "test@example.com")
      @org1.add_member(user)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
      members = @business.filtered_members(@enterprise_licensed_member1, query: "test@example.com")
      assert_equal 0, members.count
    end

    test "filters to organization owners" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, role: "owner")

        if GitHub.single_business_environment?
          assert_equal 1, members.count
        else
          assert_equal 2, members.count
          assert_members_includes members, @server_admin
        end

        assert_members_includes members, @admin
      end
    end

    test "filters to organization members" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, role: "member")

        if GitHub.single_business_environment?
          assert_equal 7, members.count
        else
          assert_equal 8, members.count
          assert_members_includes members, @volume_licensed_member2
        end

        refute_members_includes members, @admin
        assert_members_includes members, @enterprise_licensed_member1
        assert_members_includes members, @enterprise_licensed_member2
        assert_members_includes members, @volume_licensed_member1
        assert_members_includes members, @suspended1
        assert_members_includes members, @suspended2
        assert_members_includes members, @suspended_other
        assert_members_includes members, @member4
      end
    end

    unless GitHub.single_business_environment?
      test "filters to unaffiliated members with filtered members feature" do
        enable_feature_flag(:unaffiliated_user_accounts)
        enable_feature_flag(:business_user_account_filtered_members)
        user = create :user
        @business.add_user_accounts([user.id])
        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, role: "unaffiliated")
          assert_equal 1, members.count
          assert_members_includes members, user
        end
      end

      test "filters to unaffiliated members without filtered members feature" do
        enable_feature_flag(:unaffiliated_user_accounts)
        disable_feature_flag(:business_user_account_filtered_members)
        user = create :user
        @business.add_user_accounts([user.id])
        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, role: "unaffiliated")
          assert_equal 1, members.count
          assert_members_includes members, user
          members = @business.filtered_members(viewer, role: "unaffiliated", deployment: "cloud")
          assert_equal 1, members.count
          assert_members_includes members, user
        end
      end

      test "filters to unaffiliated members with batched_scope without filtered members feature" do
        enable_feature_flag(:unaffiliated_user_accounts)
        disable_feature_flag(:business_user_account_filtered_members)
        user = create :user
        @business.add_user_accounts([user.id])
        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, role: "unaffiliated", batched_scope: true)
          assert_equal 1, members.count
          assert_members_includes members, user
          members = @business.filtered_members(viewer, role: "unaffiliated", deployment: "cloud", batched_scope: true)
          assert_equal 1, members.count
          assert_members_includes members, user
        end
      end
    end

    test "shows all members if no deployment is chosen" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, deployment: nil)

        if GitHub.single_business_environment?
          assert_equal 18, members.count
          assert_members_includes members, @rando
        else
          assert_equal 11, members.count
          assert_members_includes members, @suspended1
          assert_members_includes members, @suspended2
          assert_members_includes members, @suspended_other
        end
        assert_members_includes members, @admin
        assert_members_includes members, @billing_manager
        assert_members_includes members, @server_admin
        assert_members_includes members, @enterprise_licensed_member1
        assert_members_includes members, @enterprise_licensed_member2
        assert_members_includes members, @volume_licensed_member1
        assert_members_includes members, @volume_licensed_member2
        assert_members_includes members, @member4
      end
    end

    test "shows all members if no license is chosen" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, license: nil)
        if GitHub.single_business_environment?
          assert_equal 18, members.count
          assert_members_includes members, @rando
        else
          assert_equal 11, members.count
          assert_members_includes members, @suspended1
          assert_members_includes members, @suspended2
          assert_members_includes members, @suspended_other
        end
        assert_members_includes members, @admin
        assert_members_includes members, @billing_manager
        assert_members_includes members, @server_admin
        assert_members_includes members, @enterprise_licensed_member1
        assert_members_includes members, @enterprise_licensed_member2
        assert_members_includes members, @volume_licensed_member1
        assert_members_includes members, @volume_licensed_member2
        assert_members_includes members, @member4
      end
    end

    test "ignores the value passed for license if business does not have volume licensing enabled" do
      @business.enterprise_agreements.destroy_all

      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, license: "volume")
        if GitHub.single_business_environment?
          assert_equal 18, members.count
          assert_members_includes members, @rando
        else
          assert_equal 10, members.count
          assert_members_includes members, @suspended1
          assert_members_includes members, @suspended2
          assert_members_includes members, @suspended_other
        end
        assert_members_includes members, @admin
        assert_members_includes members, @server_admin
        assert_members_includes members, @enterprise_licensed_member1
        assert_members_includes members, @enterprise_licensed_member2
        assert_members_includes members, @volume_licensed_member1
        assert_members_includes members, @volume_licensed_member2
        assert_members_includes members, @member4
      end
    end

    unless GitHub.single_business_environment?
      test "shows no members when no copilot licenses have been assigned" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, license: "copilot")
          assert_equal 0, members.count
        end
      end

      test "shows members with copilot license assigned" do
        business = create :business, seats_plan_type: :basic
        ent_team = create :copilot_enterprise_team, team_name: "team1", member_count: 0, supplied_business: business
        assignment = create(:copilot_seat_assignment, :enterprise_team, team_name: "team1", member_count: 0, supplied_business: business, business: business, supplied_enterprise_team: ent_team)
        unaffiliated = create :user
        unaffiliated2 = create :user
        admin = business.owners.first
        create :business_user_account, business: business, user: unaffiliated, business_roles_bitfield: 0
        create :business_user_account, business: business, user: unaffiliated2, business_roles_bitfield: 0
        ent_team.enterprise_team_group_mappings.destroy_all
        ent_team.bulk_add_members(users: [unaffiliated])
        EnterpriseTeamAssignment.create!(enterprise_team: ent_team, assignment_type: "copilot")
        Copilot::Business.new(business).assign([ent_team], admin)
        members = if GitHub.flipper[:business_user_account_filtered_members].enabled?
          business.filtered_members(admin, license: "copilot", include_unaffiliated: true)
        else
          business.filtered_members(admin, license: "copilot", role: "unaffiliated")
        end
        assert_equal 1, members.count
        assert_includes members.pluck(:user_id), unaffiliated.id
        if GitHub.flipper[:business_user_account_filtered_members].enabled?
          members = business.filtered_members(admin, license: "no_copilot", include_unaffiliated: true)
          assert_equal 2, members.count
          assert_includes members.pluck(:user_id), admin.id
          assert_includes members.pluck(:user_id), unaffiliated2.id
        else
          members = business.filtered_members(admin, license: "no_copilot", role: "unaffiliated")
          assert_equal 1, members.count
          assert_includes members.pluck(:user_id), unaffiliated2.id
        end
      end
    end

    test "returns no results when filtering by deployment for enterprise members" do
      viewer = @member4
      assert_empty @business.filtered_members(viewer, deployment: "server")
      assert_empty @business.filtered_members(viewer, deployment: "cloud")
    end

    if GitHub.single_business_environment?
      test "ignores the value passed for Deployment for GHES" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, deployment: "server")
          assert_equal 18, members.count
          assert_members_includes members, @admin
          assert_members_includes members, @server_admin
          assert_members_includes members, @rando
          assert_members_includes members, @enterprise_licensed_member1
          assert_members_includes members, @enterprise_licensed_member2
          assert_members_includes members, @volume_licensed_member1
          assert_members_includes members, @volume_licensed_member2
          assert_members_includes members, @member4
          refute_members_includes members, User.ghost
        end
      end

      test "ignores the value passed for Deployment for GHES for enterprise members when allowed to filter" do
        expected_members = [
          @admin,
          @enterprise_licensed_member1,
          @enterprise_licensed_member2,
          @volume_licensed_member1,
          @member4,
        ]

        members = @business.filtered_members(
          @member4,
          allow_filters_for_non_admin_viewer: true,
          deployment: "server",
        )

        expected_members.each { |m| assert_members_includes members, m }
        assert_equal expected_members.count, members.count
      end

      test "ignores the value passed for license for GHES" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, license: "enterprise")
          assert_equal 18, members.count
          assert_members_includes members, @admin
          assert_members_includes members, @server_admin
          assert_members_includes members, @rando
          assert_members_includes members, @enterprise_licensed_member1
          assert_members_includes members, @enterprise_licensed_member2
          assert_members_includes members, @volume_licensed_member1
          assert_members_includes members, @volume_licensed_member2
          assert_members_includes members, @member4
          refute_members_includes members, User.ghost
        end
      end
    else

      test "filters to members of cloud deployments" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, deployment: "cloud")
          assert_equal 9, members.count
          assert_members_includes members, @admin
          assert_members_includes members, @billing_manager
          assert_members_includes members, @enterprise_licensed_member1
          assert_members_includes members, @enterprise_licensed_member2
          assert_members_includes members, @volume_licensed_member1
          refute_members_includes members, @volume_licensed_member2
          refute_members_includes members, @server_admin
          assert_members_includes members, @suspended1
          assert_members_includes members, @suspended2
          assert_members_includes members, @suspended_other
          assert_members_includes members, @member4
        end
      end

      test "filters to members of cloud deployments for enterprise members when allowed to filter" do
        expected_members = [
          @admin,
          @enterprise_licensed_member1,
          @enterprise_licensed_member2,
          @volume_licensed_member1,
          @suspended1,
          @suspended2,
          @suspended_other,
          @member4,
        ].compact_blank!

        members = @business.filtered_members(
          @member4,
          allow_filters_for_non_admin_viewer: true,
          deployment: "cloud",
        )

        expected_members.each { |m| assert_members_includes members, m }
        assert_equal expected_members.count, members.count
      end

      test "filters to members of server deployments" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, deployment: "server")
          assert_equal 2, members.count
          assert_members_includes members, @server_admin
          assert_members_includes members, @volume_licensed_member2
        end
      end

      test "filters to members of server deployments for enterprise members when allowed to filter" do
        viewer = @member4
        bua_filtered = [viewer, @business].any? { |actor| actor.feature_enabled?(:business_user_account_filtered_members, memoize: false) }

        expected_members = [
          (@server_admin unless bua_filtered),
          (@volume_licensed_member2 unless bua_filtered),
        ].compact_blank!

        members = @business.filtered_members(
          viewer,
          allow_filters_for_non_admin_viewer: true,
          deployment: "server",
        )

        expected_members.each { |m| assert_members_includes members, m }
        assert_equal expected_members.count, members.count
      end

      test "queries server deployment users by name" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, query: "server")
          assert_equal 2, members.count
          assert_members_includes members, @volume_licensed_member2
          assert_members_includes members, @server_admin

          members = @business.filtered_members(viewer, query: "server-admin")
          assert_equal 1, members.count
          assert_members_includes members, @server_admin
        end
      end

      test "queries server deployment users by profile_name" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, query: "herp")
          assert_equal 1, members.count
          assert_members_includes members, @volume_licensed_member2
        end
      end

      test "filters to members with enterprise licenses" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, license: "enterprise")

          assert_equal 8, members.count
          assert_members_includes members, @enterprise_licensed_member1
          assert_members_includes members, @enterprise_licensed_member2
          assert_members_includes members, @admin
          assert_members_includes members, @server_admin
          refute_members_includes members, @volume_licensed_member1
          refute_members_includes members, @volume_licensed_member2
          assert_members_includes members, @suspended1
          assert_members_includes members, @suspended2
          assert_members_includes members, @suspended_other
          assert_members_includes members, @member4
        end
      end

      test "filters to members with enterprise licenses incluing server only users" do
        installation = create :enterprise_installation,
          host_name: "server1.ghes.com", owner: @business,
          customer_name: "Enterprise One"

        ei_ua = create :enterprise_installation_user_account,
               enterprise_installation: installation,
               login: "server-only-user"

        server_only_business_user_account = create :business_user_account,
          business: @business,
          login: "server-only-user",
          user: nil,
          enterprise_installation_user_accounts: [ei_ua]

        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, license: "enterprise")

          assert_equal 9, members.count
          assert_includes members, server_only_business_user_account
        end
      end

      test "filters to members with volume licenses" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, license: "vss_bundle")
          assert_equal 2, members.count
          refute_members_includes members, @enterprise_licensed_member1
          refute_members_includes members, @enterprise_licensed_member2
          assert_members_includes members, @volume_licensed_member1
          assert_members_includes members, @volume_licensed_member2
        end
      end

      test "filters to members with volume licenses when batched_scope" do
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, license: "vss_bundle", batched_scope: true)
          assert_equal 2, members.count

          refute_members_includes members, @enterprise_licensed_member1
          refute_members_includes members, @enterprise_licensed_member2
          assert_members_includes members, @volume_licensed_member1
          assert_members_includes members, @volume_licensed_member2
        end
      end

      test "filters to members with enterprise licenses incluing server only users when batched_scope" do
        installation = create :enterprise_installation,
          host_name: "server1.ghes.com", owner: @business,
          customer_name: "Enterprise One"

        ei_ua = create :enterprise_installation_user_account,
               enterprise_installation: installation,
               login: "server-only-user"

        server_only_business_user_account = create :business_user_account,
          business: @business,
          login: "server-only-user",
          user: nil,
          enterprise_installation_user_accounts: [ei_ua]

        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          members = @business.filtered_members(viewer, license: "enterprise", batched_scope: true)

          assert_equal 9, members.count
          assert_includes members, server_only_business_user_account
        end
      end

      test "no users are returned when the deployment:'server' and two_factor filters are enabled at the same time" do
        disable_feature_flag(:business_user_account_filtered_members)
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          server_users = @business.filtered_members(viewer, deployment: "server")
          server_and_two_factor_disabled_members = @business.filtered_members(@admin, deployment: "server", two_factor: :disabled)

          # Check that server_users has at least one member with 2FA disabled
          refute server_users.select { |user| !user.two_factor_authentication_enabled? }.empty?
          assert server_and_two_factor_disabled_members.empty?
        end
      end

      test "users are returned when the deployment:'server' and two_factor filters are enabled at the same time" do
        enable_feature_flag(:business_user_account_filtered_members)
        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          server_users = @business.filtered_members(viewer, deployment: "server")
          server_and_two_factor_disabled_members = @business.filtered_members(@admin, deployment: "server", two_factor: :disabled)

          two_fa_users = server_users.select { |user| !user.two_factor_authentication_enabled? }
          assert_equal two_fa_users.size, server_and_two_factor_disabled_members.size
          server_users.each { |user| assert_includes server_and_two_factor_disabled_members, user }
        end
      end

      test "server-only users are excluded from filtered_members if two_factor is set to :enabled, :required or :disabled" do
        # A BusinessUserAccount with no user_id is a server-only account.
        # A BusinessUserAccount with a user_id is a cloud account that may or may not be associated with a server.
        # What determines whether a BusinessUserAccount is associated with a server is whether the BUA also
        # has an EnterpriseInstallationUserAccount tied to it.
        server_only_bua = create(:business_user_account, user: nil, business: @business)
        create :enterprise_installation_user_account, \
          enterprise_installation: @business_installation,
          profile_name: "server-only-user",
          business_user_account: server_only_bua
        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          two_factor_members = @business.filtered_members(viewer, two_factor: :enabled) + @business.filtered_members(viewer, two_factor: :disabled) + @business.filtered_members(viewer, two_factor: :required)

          refute_includes two_factor_members, server_only_bua
        end
      end

      test "server-only users are included in filtered_members if two_factor is set to nil, for a GHEC business" do
        server_only_bua = create(:business_user_account, user: nil, business: @business)
        create :enterprise_installation_user_account, \
          enterprise_installation: @business_installation,
          profile_name: "server-only-user",
          business_user_account: server_only_bua
        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          all_members = @business.filtered_members(viewer, two_factor: nil)

          assert_includes all_members, server_only_bua
        end
      end
    end

    test "returns members with 2FA enabled when two_factor is set to enabled" do
      two_fa_enabled_user = create :user, login: "two-fa-enabled-user"
      two_fa_enabled_user.two_factor_credential = create :two_factor_credential
      @business.organizations.first.add_member(two_fa_enabled_user)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, two_factor: :enabled)

        assert_equal 1, members.count
        assert_members_includes members, two_fa_enabled_user
      end
    end

    test "returns members with 2FA enabled when two_factor is set to required" do
      two_fa_enabled_user = create :user, login: "two-fa-enabled-user"
      two_fa_disabled_user = create :user, login: "two-fa-disabled-user"
      @business.organizations.first.add_member(two_fa_enabled_user)
      @business.organizations.first.add_member(two_fa_disabled_user)
      two_fa_required_user = create :user, login: "two-fa-required-user"
      TwoFactorRequirementMetadata.create!(user: two_fa_required_user, requirement_reason: "test", state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required])
      @business.organizations.first.add_member(two_fa_required_user)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        members = @business.filtered_members(viewer, two_factor: :required)

        assert_members_includes members, two_fa_required_user
        refute_members_includes members, two_fa_enabled_user
        refute_members_includes members, two_fa_disabled_user
      end
    end

    test "returns members with 2FA disabled when two_factor is set to disabled." do
      two_fa_enabled_user = create :user, login: "two-fa-enabled-user"
      two_fa_enabled_user.two_factor_credential = create :two_factor_credential
      @business.organizations.first.add_member(two_fa_enabled_user)
      two_fa_disabled_user = create :user, login: "two-fa-disabled-user"
      @business.organizations.first.add_member(two_fa_disabled_user)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        two_fa_disabled_members = @business.filtered_members(viewer, two_factor: :disabled)
        two_fa_enabled_members = @business.filtered_members(viewer, two_factor: :enabled)

        assert_members_includes two_fa_disabled_members, two_fa_disabled_user
        refute_members_includes two_fa_disabled_members, two_fa_enabled_user
      end
    end

    if GitHub.two_factor_sms_enabled?
      test "returns members with secure or insecure 2FA methods when two_factor is set to secure or insecure" do
        disable_feature_flag(:business_user_account_filtered_members)
        two_fa_secure_user = create :user, login: "two-fa-secure-user"
        make_two_factor_credential(two_fa_secure_user)
        @business.organizations.first.add_member(two_fa_secure_user)

        two_fa_insecure_user = create :user, login: "two-fa-sms-user"
        make_sms_two_factor_credential(two_fa_insecure_user)
        @business.organizations.first.add_member(two_fa_insecure_user)

        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          two_fa_secure_members = @business.filtered_members(viewer, two_factor: :secure)
          two_fa_insecure_members = @business.filtered_members(viewer, two_factor: :insecure)

          assert_members_includes two_fa_secure_members, two_fa_secure_user
          refute_members_includes two_fa_insecure_members, two_fa_secure_user
          assert_members_includes two_fa_insecure_members, two_fa_insecure_user
          refute_members_includes two_fa_secure_members, two_fa_insecure_user
        end
      end
    end

    test "returns all members, regardless of two_factor status, when two_factor is set to nil." do
      two_fa_enabled_user = create :user, login: "two-fa-enabled-user"
      two_fa_enabled_user.two_factor_credential = create :two_factor_credential
      @business.organizations.first.add_member(two_fa_enabled_user)
      two_fa_disabled_user = create :user, login: "two-fa-disabled-user"
      @business.organizations.first.add_member(two_fa_disabled_user)
      two_fa_required_user = create :user, login: "two-fa-required-user"
      TwoFactorRequirementMetadata.create!(user: two_fa_required_user, requirement_reason: "test", state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required])
      @business.organizations.first.add_member(two_fa_required_user)

      # In the fixtures, these two users don't belong to any orgs in the business.
      # They need to be added to an org in the business in order to be returned by
      # filtered_members when the two_factor filter is toggled on.
      @business.organizations.first.add_member(@server_admin)
      @business.organizations.first.add_member(@volume_licensed_member2)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        all_members = @business.filtered_members(viewer, two_factor: nil)
        two_fa_disabled_members = @business.filtered_members(viewer, two_factor: :disabled)
        two_fa_enabled_members = @business.filtered_members(viewer, two_factor: :enabled)
        two_fa_required_members = @business.filtered_members(viewer, two_factor: :required)

        assert_members_includes two_fa_disabled_members, two_fa_disabled_user
        assert_members_includes two_fa_enabled_members, two_fa_enabled_user
        assert_members_includes two_fa_required_members, two_fa_required_user
        assert_same_elements (two_fa_disabled_members + two_fa_enabled_members + two_fa_required_members).uniq, all_members
      end
    end

    test "returns all members, regardless of two_factor status, when two_factor is set to a random argument" do
      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        random_argument_users = @business.filtered_members(viewer, two_factor: :random)
        all_users = @business.filtered_members(viewer)

        refute all_users.empty?
        assert_same_elements all_users, random_argument_users
      end
    end

    test "checks that 2FA-enabled admins are returned with members" do
      two_fa_enabled_user = create :user, login: "two-fa-enabled-user"
      two_fa_enabled_admin = create :user, login: "two-fa-enabled-admin"
      two_fa_disabled_admin = create :user, login: "two-fa-disabled-admin"
      two_fa_required_admin = create :user, login: "two-fa-required-admin"
      TwoFactorRequirementMetadata.create!(user: two_fa_required_admin, requirement_reason: "test", state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required])
      two_fa_enabled_user.two_factor_credential = create :two_factor_credential
      two_fa_enabled_admin.two_factor_credential = create :two_factor_credential
      @business.organizations.first.add_member(two_fa_enabled_user)
      @business.add_owner(two_fa_enabled_admin, actor: @admin)
      @business.add_owner(two_fa_disabled_admin, actor: @admin)
      @business.add_owner(two_fa_required_admin, actor: @admin)

      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        two_fa_enabled_users = @business.filtered_members(viewer, two_factor: :enabled)

        assert_members_includes two_fa_enabled_users, two_fa_enabled_user
        assert_members_includes two_fa_enabled_users, two_fa_enabled_admin
        refute_members_includes two_fa_enabled_users, two_fa_disabled_admin
        refute_members_includes two_fa_enabled_users, two_fa_required_admin
        assert_equal two_fa_enabled_users.count, 2
      end
    end

    test "checks that 2FA-required admins are returned with members" do
      two_fa_enabled_admin = create :user, login: "two-fa-enabled-admin"
      two_fa_disabled_admin = create :user, login: "two-fa-disabled-admin"
      two_fa_required_admin = create :user, login: "two-fa-required-admin"
      TwoFactorRequirementMetadata.create!(user: two_fa_required_admin, requirement_reason: "test", state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required])
      two_fa_enabled_admin.two_factor_credential = create :two_factor_credential

      @business.add_owner(two_fa_enabled_admin, actor: @admin)
      @business.add_owner(two_fa_disabled_admin, actor: @admin)
      @business.add_owner(two_fa_required_admin, actor: @admin)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        two_fa_required_users = @business.filtered_members(viewer, two_factor: :required)

        assert_members_includes two_fa_required_users, two_fa_required_admin
        refute_members_includes two_fa_required_users, two_fa_disabled_admin
        refute_members_includes two_fa_required_users, two_fa_enabled_admin
      end
    end

    test "checks that 2FA-disabled admins are returned with members" do
      two_fa_enabled_admin = create :user, login: "two-fa-enabled-admin"
      two_fa_disabled_admin = create :user, login: "two-fa-disabled-admin"
      two_fa_required_admin = create :user, login: "two-fa-required-admin"
      TwoFactorRequirementMetadata.create!(user: two_fa_required_admin, requirement_reason: "test", state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required])
      two_fa_enabled_admin.two_factor_credential = create :two_factor_credential

      @business.add_owner(two_fa_enabled_admin, actor: @admin)
      @business.add_owner(two_fa_disabled_admin, actor: @admin)
      @business.add_owner(two_fa_required_admin, actor: @admin)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)

      setup_member_with_read_enterprise_admins_and_members(@member4)
      [@admin, @member4].each do |viewer|
        two_fa_disabled_users = @business.filtered_members(viewer, two_factor: :disabled)

        if @business.feature_enabled?(:business_user_account_filtered_members)
          # for BUAs, required and disabled are exclusive b/c status is stored as a state
          refute_members_includes two_fa_disabled_users, two_fa_required_admin
        else
          assert_members_includes two_fa_disabled_users, two_fa_required_admin
        end
        refute_members_includes two_fa_disabled_users, two_fa_enabled_admin
        assert_members_includes two_fa_disabled_users, two_fa_disabled_admin
      end
    end

    context "when filtering by cost center" do
      test "only includes cost center users for non-batched scope" do
        stub_cost_center

        expected_buas = [@enterprise_licensed_member1, @volume_licensed_member1, @cloud_and_server_user, @server_admin].map do |user|
          user.business_user_accounts.find_by!(business_id: @business.id)
        end

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: "test-cost-center")
          assert_same_elements(expected_buas, filtered_members)
        end
      end

      test "only includes cloud users that are part of the cost center for non-batched scope" do
        stub_cost_center

        expected_buas = [@enterprise_licensed_member1, @volume_licensed_member1, @cloud_and_server_user].map do |user|
          user.business_user_accounts.find_by!(business_id: @business.id)
        end

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: "test-cost-center", deployment: "cloud")
          assert_same_elements(expected_buas, filtered_members)
        end
      end

      test "only includes server users that have GitHub user accounts and are part of the cost center for non-batched scope" do
        stub_cost_center

        expected_buas = [@cloud_and_server_user, @server_admin].map do |user|
          user.business_user_accounts.find_by!(business_id: @business.id)
        end

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: "test-cost-center", deployment: "server")
          assert_same_elements(expected_buas, filtered_members)
        end
      end

      test "NO_COST_CENTER excludes users with any cost center for non-batched scope" do
        stub_cost_center

        unexpected_buas = [@enterprise_licensed_member1, @volume_licensed_member1, @cloud_and_server_user, @server_admin].map do |user|
          user.business_user_accounts.find_by!(business_id: @business.id)
        end

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: Business::PeopleDependency::FILTER_VALUE_NO_COST_CENTER)

          refute_empty(filtered_members)
          unexpected_buas.each { |bua| refute_includes filtered_members, bua }
          assert_includes filtered_members, @server_only_bua
        end
      end

      test "a cost center with no members returns no results for non-batched scop" do
        stub_cost_center

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: "empty-cost-center")

          assert_empty(filtered_members)
        end
      end

      test "only includes cost center users for batched scope" do
        stub_cost_center

        expected_buas = [@enterprise_licensed_member1, @volume_licensed_member1, @cloud_and_server_user, @server_admin].map do |user|
          user.business_user_accounts.find_by!(business_id: @business.id)
        end

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: "test-cost-center", batched_scope: true)
          assert_same_elements(expected_buas, filtered_members)
        end
      end

      test "only includes cloud users that are part of the cost center for batched scope" do
        stub_cost_center

        expected_buas = [@enterprise_licensed_member1, @volume_licensed_member1, @cloud_and_server_user].map do |user|
          user.business_user_accounts.find_by!(business_id: @business.id)
        end

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: "test-cost-center", batched_scope: true, deployment: "cloud")
          assert_same_elements(expected_buas, filtered_members)
        end
      end

      test "only includes server users that have GitHub user accounts and are part of the cost center for batched scope" do
        stub_cost_center

        expected_buas = [@cloud_and_server_user, @server_admin].map do |user|
          user.business_user_accounts.find_by!(business_id: @business.id)
        end

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: "test-cost-center", batched_scope: true, deployment: "server")
          assert_same_elements(expected_buas, filtered_members)
        end
      end

      test "NO_COST_CENTER excludes users with any cost center for batched scope" do
        stub_cost_center

        unexpected_buas = [@enterprise_licensed_member1, @volume_licensed_member1, @cloud_and_server_user, @server_admin].map do |user|
          user.business_user_accounts.find_by!(business_id: @business.id)
        end

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: Business::PeopleDependency::FILTER_VALUE_NO_COST_CENTER, batched_scope: true)

          refute_empty(filtered_members)
          unexpected_buas.each { |bua| refute_includes filtered_members, bua }
          assert_includes filtered_members, @server_only_bua
        end
      end

      test "a cost center with no members returns no results for batched scop" do
        stub_cost_center

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: "empty-cost-center", batched_scope: true)

          assert_empty(filtered_members)
        end
      end

      test "only includes cost center users for bua_filtered_members" do
        enable_feature_flag(:business_user_account_filtered_members, @business)
        stub_cost_center

        expected_buas = [@enterprise_licensed_member1, @volume_licensed_member1, @cloud_and_server_user, @server_admin].map do |user|
          user.business_user_accounts.find_by!(business_id: @business.id)
        end

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: "test-cost-center")
          assert_same_elements(expected_buas, filtered_members)
        end
      end

      test "only includes cloud users that are part of the cost center for bua_filtered_members" do
        enable_feature_flag(:business_user_account_filtered_members, @business)
        stub_cost_center

        expected_buas = [@enterprise_licensed_member1, @volume_licensed_member1, @cloud_and_server_user].map do |user|
          user.business_user_accounts.find_by!(business_id: @business.id)
        end

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: "test-cost-center", deployment: "cloud")
          assert_same_elements(expected_buas, filtered_members)
        end
      end

      test "only includes server users that have GitHub user accounts and are part of the cost center for bua_filtered_members" do
        enable_feature_flag(:business_user_account_filtered_members, @business)
        stub_cost_center

        expected_buas = [@cloud_and_server_user, @server_admin].map do |user|
          user.business_user_accounts.find_by!(business_id: @business.id)
        end

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: "test-cost-center", deployment: "server")
          assert_same_elements(expected_buas, filtered_members)
        end
      end

      test "NO_COST_CENTER excludes users with any cost center for bua_filtered_members" do
        enable_feature_flag(:business_user_account_filtered_members, @business)
        stub_cost_center

        unexpected_buas = [@enterprise_licensed_member1, @volume_licensed_member1, @cloud_and_server_user, @server_admin].map do |user|
          user.business_user_accounts.find_by!(business_id: @business.id)
        end

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: Business::PeopleDependency::FILTER_VALUE_NO_COST_CENTER, batched_scope: true)

          refute_empty(filtered_members)
          unexpected_buas.each { |bua| refute_includes filtered_members, bua }
          assert_includes filtered_members, @server_only_bua
        end
      end

      test "a cost center with no members returns no results for bua_filtered_members" do
        enable_feature_flag(:business_user_account_filtered_members, @business)
        stub_cost_center

        setup_member_with_read_enterprise_admins_and_members(@member4)
        [@admin, @member4].each do |viewer|
          filtered_members = @business.filtered_members(viewer, cost_center: "empty-cost-center")

          assert_empty(filtered_members)
        end
      end
    end unless GitHub.single_business_environment?
  end

  if GitHub.repo_invites_enabled?
    context "#filtered_outside_collaborators" do
      test "loads all outside collaborators by default" do
        collaborators = @business.filtered_outside_collaborators
        assert_same_elements [@collaborator1, @collaborator2, @collaborator3], collaborators
      end

      test "includes spammy outside collaborators" do
        spammer = create :user, spammy: true
        @repo1.add_member(spammer)

        collaborators = @business.filtered_outside_collaborators
        assert_same_elements [@collaborator1, @collaborator2, @collaborator3, spammer], collaborators
      end

      test "orders outside collaborators by login ascending by default" do
        collaborators = @business.filtered_outside_collaborators
        expected = %w[collaborator1 collaborator2 other-collab]
        assert_equal expected, collaborators.map(&:login)
      end

      test "orders outside collaborators using order by arguments when provided" do
        collaborators = @business.filtered_outside_collaborators(
          order_by_field: "login",
          order_by_direction: "desc",
        )
        expected = %w[other-collab collaborator2 collaborator1]
        assert_equal expected, collaborators.map(&:login)
      end

      test "ignores invalid ordering arguments" do
        collaborators = @business.filtered_outside_collaborators(
          order_by_field: "invalid field",
          order_by_direction: "invalid direction",
        )
        expected = %w[collaborator1 collaborator2 other-collab]
        assert_equal expected, collaborators.map(&:login)
      end

      test "queries for collaborators by login" do
        collaborators = @business.filtered_outside_collaborators(query: "collaborator")
        assert_same_elements [@collaborator1, @collaborator2], collaborators

        collaborators = @business.filtered_outside_collaborators(query: "collaborator1")
        assert_same_elements [@collaborator1], collaborators
      end

      test "queries for collaborators by profile name" do
        collaborators = @business.filtered_outside_collaborators(query: "name")
        assert_same_elements [@collaborator1], collaborators
      end

      test "queries for collaborators by email as owner" do
        create(:user_email, :verified, user: @collaborator1, email: "test@example.com")
        collaborators = @business.filtered_outside_collaborators(query: "test@example.com", viewer: @admin)
        assert_same_elements [@collaborator1], collaborators
      end

      test "queries for collaborators by email as user" do
        create(:user_email, :verified, user: @collaborator1, email: "test@example.com")
        collaborators = @business.filtered_outside_collaborators(query: "test@example.com")
        assert_same_elements [], collaborators
      end

      test "finds collaborators for private repository visibility" do
        collaborators = @business.filtered_outside_collaborators(visibility: [:private])
        assert_same_elements [@collaborator2], collaborators
      end

      test "finds collaborators for public repository visibility" do
        collaborators = @business.filtered_outside_collaborators(visibility: [:public])
        assert_same_elements [@collaborator1, @collaborator3], collaborators
      end

      test "finds collaborators with 2FA enabled" do
        @collaborator1.two_factor_credential = create :two_factor_credential

        assert @collaborator1.two_factor_authentication_enabled?
        refute @collaborator2.two_factor_authentication_enabled?, @collaborator3.two_factor_authentication_enabled?

        collaborators = @business.filtered_outside_collaborators(two_factor: :enabled)

        assert_same_elements [@collaborator1], collaborators
      end

      test "finds collaborators with 2FA required" do
        @collaborator1.two_factor_credential = create :two_factor_credential
        TwoFactorRequirementMetadata.create!(user: @collaborator2, requirement_reason: "test", state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required])

        assert @collaborator1.two_factor_authentication_enabled?
        refute @collaborator2.two_factor_authentication_enabled?, @collaborator3.two_factor_authentication_enabled?

        collaborators = @business.filtered_outside_collaborators(two_factor: :required)

        assert_same_elements [@collaborator2], collaborators
      end

      test "finds collaborators with 2FA disabled" do
        @collaborator1.two_factor_credential = create :two_factor_credential

        assert @collaborator1.two_factor_authentication_enabled?
        refute @collaborator2.two_factor_authentication_enabled?, @collaborator3.two_factor_authentication_enabled?

        collaborators = @business.filtered_outside_collaborators(two_factor: :disabled)

        assert_same_elements [@collaborator2, @collaborator3], collaborators
      end

      if GitHub.two_factor_sms_enabled?
        test "finds collaborators with secure 2FA methods" do
          make_two_factor_credential(@collaborator1)
          make_sms_two_factor_credential(@collaborator2)

          assert @collaborator1.two_factor_authentication_enabled?, @collaborator2.two_factor_authentication_enabled?
          refute @collaborator3.two_factor_authentication_enabled?

          collaborators = @business.filtered_outside_collaborators(two_factor: :secure)

          assert_same_elements [@collaborator1], collaborators
        end

        test "finds collaborators with insecure 2FA methods" do
          make_two_factor_credential(@collaborator1)
          make_sms_two_factor_credential(@collaborator2)

          assert @collaborator1.two_factor_authentication_enabled?, @collaborator2.two_factor_authentication_enabled?
          refute @collaborator3.two_factor_authentication_enabled?

          collaborators = @business.filtered_outside_collaborators(two_factor: :insecure)

          assert_same_elements [@collaborator2], collaborators
        end
      end

      test "finds exactly one collaborator by login argument" do
        collaborators = @business.filtered_outside_collaborators(login: "collaborator2")
        assert_same_elements [@collaborator2], collaborators
      end

      test "finds zero collaborators if login argument doesn't match" do
        collaborators = @business.filtered_outside_collaborators(login: "collaborator")
        assert_empty collaborators
      end

      test "filters collaborators by organization name if org name matches" do
        collaborators = @business.filtered_outside_collaborators(organizations: [@org1.name])
        assert_same_elements [@collaborator1, @collaborator3], collaborators
      end

      test "filters collaborators by multiple organizations if org names match" do
        collaborators = @business.filtered_outside_collaborators(organizations: [@org1.name, @org2.name])
        assert_same_elements [@collaborator1, @collaborator2, @collaborator3], collaborators
      end

      test "finds zero collaborators if org name argument does not match exactly" do
        assert_empty @business.filtered_outside_collaborators(organizations: ["non-existent-org"])
        assert_empty @business.filtered_outside_collaborators(organizations: [@org1.name[0..-2]])
      end
    end
  end

  context "#all_member_ids" do
    test "includes ids for all admins and org members" do
      member_ids = @business.all_member_ids

      if GitHub.single_business_environment?
        assert_equal 18, member_ids.count
        assert member_ids.include?(@rando.id)
      else
        assert_equal 10, member_ids.count
        assert member_ids.include?(@suspended1.id)
        assert member_ids.include?(@suspended2.id)
        assert member_ids.include?(@suspended_other.id)
      end

      assert member_ids.include?(@admin.id)
      assert member_ids.include?(@enterprise_licensed_member1.id)
      assert member_ids.include?(@enterprise_licensed_member2.id)
      assert member_ids.include?(@volume_licensed_member1.id)
      assert member_ids.include?(@volume_licensed_member2.id)
      assert member_ids.include?(@server_admin.id)
      assert member_ids.include?(@member4.id)
    end

    if GitHub.single_business_environment?
      test "returns the same results as #filtered_members for GHES" do
        assert_equal @business.filtered_members(@admin).pluck(:id).sort, @business.all_member_ids.sort
      end
    else
      test "returns the same results as #filtered_members without billing managers for GHEC" do
        expected_members = @business.filtered_members(@admin).pluck(:user_id).sort
        expected_members -= @business.billing_managers.pluck(:id)

        assert_equal expected_members, @business.all_member_ids.sort
      end
    end
  end

  context "#pending_admin_invitations" do
    test "loads both owner and billing manager invitations by default" do
      invitee1 = create :user
      invitee2 = create :user
      owner_invitation1 = create :business_administrator_invitation,
                          role: :owner, business: @business, inviter: @admin, invitee: invitee1
      owner_invitation2 = create :business_administrator_invitation,
                          role: :owner, business: @business, inviter: @admin, invitee: invitee2
      billing_invitation = create :business_administrator_invitation,
                           role: :billing_manager, business: @business, inviter: @admin, invitee: invitee1
      pending_invitations = @business.pending_admin_invitations
      assert_same_elements [owner_invitation1, owner_invitation2, billing_invitation], pending_invitations
    end

    test "loads both owner and billing manager invitations when nil is passed to role" do
      invitee1 = create :user
      invitee2 = create :user
      owner_invitation1 = create :business_administrator_invitation,
                          role: :owner, business: @business, inviter: @admin, invitee: invitee1
      owner_invitation2 = create :business_administrator_invitation,
                          role: :owner, business: @business, inviter: @admin, invitee: invitee2
      billing_invitation = create :business_administrator_invitation,
                           role: :billing_manager, business: @business, inviter: @admin, invitee: invitee1
      pending_invitations = @business.pending_admin_invitations(role: nil)
      assert_same_elements [owner_invitation1, owner_invitation2, billing_invitation], pending_invitations
    end


    test "returns only owner invitations when :owner role is provided" do
      invitee1 = create :user
      invitee2 = create :user
      owner_invitation1 = create :business_administrator_invitation,
                          role: :owner, business: @business, inviter: @admin, invitee: invitee1
      owner_invitation2 = create :business_administrator_invitation,
                          role: :owner, business: @business, inviter: @admin, invitee: invitee2
      create :business_administrator_invitation,
              role: :billing_manager, business: @business, inviter: @admin, invitee: invitee1
      pending_invitations = @business.pending_admin_invitations(role: :owner)
      assert_same_elements [owner_invitation1, owner_invitation2], pending_invitations
    end

    test "returns only billing manager invitations when :billing_manager role is provided" do
      invitee1 = create :user
      invitee2 = create :user
      create :business_administrator_invitation,
              role: :owner, business: @business, inviter: @admin, invitee: invitee1
      billing_invitation = create :business_administrator_invitation,
                           role: :billing_manager, business: @business, inviter: @admin, invitee: invitee2
      pending_invitations = @business.pending_admin_invitations(role: :billing_manager)
      assert_same_elements [billing_invitation], pending_invitations
    end

    test "loads invitations matching query" do
      invitee1 = create :user, login: "user-one"
      invitee2 = create :user, login: "user-two"
      invitation = create :business_administrator_invitation,
                           role: :owner, business: @business, inviter: @admin, invitee: invitee1
      create :business_administrator_invitation,
              role: :owner, business: @business, inviter: @admin, invitee: invitee2
      pending_invitations = @business.pending_admin_invitations(query: "one")
      assert_same_elements [invitation], pending_invitations
    end

    test "can filter by a specific user login" do
      invitee1 = create :user, login: "user-one"
      invitee2 = create :user, login: "user-two"
      invitation = create :business_administrator_invitation,
                           role: :owner, business: @business, inviter: @admin, invitee: invitee1
      create :business_administrator_invitation,
              role: :owner, business: @business, inviter: @admin, invitee: invitee2
      pending_invitations = @business.pending_admin_invitations(login: invitee1.login)
      assert_same_elements [invitation], pending_invitations
    end

    test "orders results by created_at descending by default" do
      invitation1 = create :business_administrator_invitation,
                            role: :owner, business: @business, inviter: @admin, invitee: create(:user),
                            created_at: DateTime.now - 1.day
      invitation2 = create :business_administrator_invitation,
                            role: :owner, business: @business, inviter: @admin, invitee: create(:user)

      expected_ids = [invitation2.id, invitation1.id]
      invitations = @business.pending_admin_invitations
      assert_equal expected_ids, invitations.pluck(:id)
    end

    test "can order results by created_at asc" do
      invitation1 = create :business_administrator_invitation,
                            role: :owner, business: @business, inviter: @admin, invitee: create(:user),
                            created_at: DateTime.now - 1.day
      invitation2 = create :business_administrator_invitation,
                            role: :owner, business: @business, inviter: @admin, invitee: create(:user)

      expected_ids = [invitation1.id, invitation2.id]
      invitations = @business.pending_admin_invitations(
        order_by_field: "created_at",
        order_by_direction: "asc",
      )
      assert_equal expected_ids, invitations.pluck(:id)
    end

    test "can order results by created_at desc" do
      invitation1 = create :business_administrator_invitation,
                            role: :owner, business: @business, inviter: @admin, invitee: create(:user),
                            created_at: DateTime.now - 1.day
      invitation2 = create :business_administrator_invitation,
                            role: :owner, business: @business, inviter: @admin, invitee: create(:user)

      expected_ids = [invitation2.id, invitation1.id]
      invitations = @business.pending_admin_invitations(
        order_by_field: "created_at",
        order_by_direction: "desc",
      )
      assert_equal expected_ids, invitations.pluck(:id)
    end

    test "can order results by title asc" do
      invitation1 = create :business_administrator_invitation,
                            role: :owner, business: @business, inviter: @admin, invitee: create(:user, name: "a"),
                            created_at: DateTime.now - 1.day
      invitation2 = create :business_administrator_invitation,
                            role: :owner, business: @business, inviter: @admin, invitee: create(:user, name: "b")

      expected_ids = [invitation1.id, invitation2.id]
      invitations = @business.pending_admin_invitations(
        order_by_field: "title",
        order_by_direction: "asc",
      )
      assert_equal expected_ids, invitations.pluck(:id)
    end

    test "can order results by title desc" do
      invitation1 = create :business_administrator_invitation,
                            role: :owner, business: @business, inviter: @admin, invitee: create(:user, name: "a"),
                            created_at: DateTime.now - 1.day
      invitation2 = create :business_administrator_invitation,
                            role: :owner, business: @business, inviter: @admin, invitee: create(:user, name: "b")

      expected_ids = [invitation2.id, invitation1.id]
      invitations = @business.pending_admin_invitations(
        order_by_field: "title",
        order_by_direction: "desc",
      )
      assert_equal expected_ids, invitations.pluck(:id)
    end
    test "ignores invalid ordering" do
      invitation1 = create :business_administrator_invitation,
                            role: :owner, business: @business, inviter: @admin, invitee: create(:user),
                            created_at: DateTime.now - 1.day
      invitation2 = create :business_administrator_invitation,
                            role: :owner, business: @business, inviter: @admin, invitee: create(:user)

      expected_ids = [invitation2.id, invitation1.id]
      invitations = @business.pending_admin_invitations(
        order_by_field: "invalid field",
        order_by_direction: "invalid direction",
      )
      assert_equal expected_ids, invitations.pluck(:id)
    end
  end

  context "#admins" do
    test "loads all owners and billing managers by default" do
      owner2 = create :user
      @business.add_owner(owner2, actor: @admin)
      assert_same_elements [@admin, owner2, @billing_manager], @business.admins
    end

    test "loads admins matching query" do
      assert_same_elements [@admin], @business.admins(query: @admin.login)
    end

    test "loads only owners when :owner role is supplied" do
      assert_same_elements [@admin], @business.admins(role: Business::OWNER_ROLE)
    end

    test "loads only billing managers when :billing_manager role is supplied" do
      assert_same_elements [@billing_manager], @business.admins(role: Business::BILLING_MANAGER_ROLE)
    end

    test "loads admins with org membership when organization is supplied" do
      org4 = create :organization, admin: @admin
      @business.add_organization org4
      assert_same_elements [@admin], @business.admins(organization_logins: org4.login)
    end

    test "does not load admins when organization is supplied but does not match any orgs in the business" do
      org4 = create :organization, admin: @admin
      @business.add_organization org4
      assert_empty @business.admins(organization_logins: org4.login + "foo")
    end

    test "does not load admins without org membership when organization is supplied" do
      org4 = create :organization, admin: @member1
      @business.add_organization org4
      assert_same_elements [], @business.admins(organization_logins: org4.login)
    end

    test "loads admins with org membership when multiple organizations are supplied" do
      owner2 = create :user
      @business.add_owner(owner2, actor: @admin)
      org4 = create :organization, admin: owner2
      @business.add_organization org4
      assert_same_elements [@admin, owner2], @business.admins(organization_logins: [org4.login, @org1.login])
      @business.remove_owner(owner2, actor: @admin)
    end

    test "loads admins with org membership when real and random logins are supplied" do
      org4 = create :organization, admin: @admin
      @business.add_organization org4
      assert_same_elements [@admin], @business.admins(organization_logins: [org4.login, "random-org"])
    end

    test "does not filter admins from non-business organizations" do
      org4 = create :organization, admin: @admin
      assert_same_elements [], @business.admins(organization_logins: org4.login)
    end

    test "orders results by login ascending by default" do
      owner2 = create :user, login: "zzzzz"
      @business.add_owner(owner2, actor: @admin)

      admins = @business.admins(role: :owner)
      assert_equal [@admin.login, owner2.login], admins.pluck(:login)
    end

    test "can order results when ordering arguments provided" do
      owner2 = create :user, login: "zzzzz"
      @business.add_owner(owner2, actor: @admin)

      admins = @business.admins(
        role: :owner,
        order_by_field: "login",
        order_by_direction: "DESC",
      )
      expected = [owner2.login, @admin.login]
      assert_equal expected, admins.pluck(:login)
    end

    test "ignores invalid ordering arguments" do
      owner2 = create :user, login: "zzzzz"
      @business.add_owner(owner2, actor: @admin)

      admins = @business.admins(
        role: :owner,
        order_by_field: "not a valid field",
        order_by_direction: "not a valid direction",
      )
      assert_equal [@admin.login, owner2.login], admins.pluck(:login)
    end

    test "ignores invalid role parameter and returns administrators with all roles" do
      assert_same_elements [@admin, @billing_manager], @business.admins(role: :invalid)
    end

    test "returns admins with 2FA enabled when two_factor is set to enabled" do
      @admin.two_factor_credential = create :two_factor_credential
      admins = @business.admins(two_factor: :enabled)
      assert_same_elements [@admin], admins
    end

    test "returns admins with 2FA enabled when two_factor is set to required" do
      TwoFactorRequirementMetadata.create!(user: @admin, requirement_reason: "test", state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:required])
      admins = @business.admins(two_factor: :required)
      assert_same_elements [@admin], admins
    end

    if GitHub.two_factor_sms_enabled?
      test "returns admins with secure 2FA methods when two_factor is set to secure" do
        make_two_factor_credential(@admin)

        admins = @business.admins(two_factor: :secure)
        assert_same_elements [@admin], admins
      end

      test "returns admins with insecure 2FA methods when two_factor is set to insecure" do
        make_sms_two_factor_credential(@admin)

        admins = @business.admins(two_factor: :insecure)
        assert_same_elements [@admin], admins
      end
    end

    test "returns admins with 2FA disabled when two_factor is set to disabled" do
      @admin.two_factor_credential = create :two_factor_credential
      admins = @business.admins(two_factor: :disabled)
      assert_same_elements [@billing_manager], admins
    end

    test "returns all admins, regardless of two_factor status, when two_factor is set to nil" do
      @admin.two_factor_credential = create :two_factor_credential
      admins = @business.admins(two_factor: nil)
      assert_same_elements [@billing_manager, @admin], admins
    end

    test "returns all admins, regardless of two_factor status, when two_factor is set to a random argument" do
      @admin.two_factor_credential = create :two_factor_credential
      admins = @business.admins(two_factor: :random)
      assert_same_elements [@billing_manager, @admin], admins
    end
  end

  context "#pending_unaffiliated_invitations" do
    test "loads unaffiliated invitations" do
      invitee1 = create :user
      invitee2 = create :user
      invitation1 = create :business_administrator_invitation,
                          role: :unaffiliated, business: @business, inviter: @admin, invitee: invitee1
      invitation2 = create :business_administrator_invitation,
                          role: :unaffiliated, business: @business, inviter: @admin, invitee: invitee2
      pending_invitations = @business.pending_unaffiliated_invitations
      assert_same_elements [invitation1, invitation2], pending_invitations
    end

    test "loads invitations matching query" do
      invitee1 = create :user, login: "user-one"
      invitee2 = create :user, login: "user-two"
      invitation = create :business_administrator_invitation,
                           role: :unaffiliated, business: @business, inviter: @admin, invitee: invitee1
      create :business_administrator_invitation,
              role: :unaffiliated, business: @business, inviter: @admin, invitee: invitee2
      pending_invitations = @business.pending_unaffiliated_invitations(query: "one")
      assert_same_elements [invitation], pending_invitations
    end

    test "can filter by a specific user login" do
      invitee1 = create :user, login: "user-one"
      invitee2 = create :user, login: "user-two"
      invitation = create :business_administrator_invitation,
                           role: :unaffiliated, business: @business, inviter: @admin, invitee: invitee1
      create :business_administrator_invitation,
              role: :unaffiliated, business: @business, inviter: @admin, invitee: invitee2
      pending_invitations = @business.pending_unaffiliated_invitations(login: invitee1.login)
      assert_same_elements [invitation], pending_invitations
    end

    test "orders results by created_at descending by default" do
      invitation1 = create :business_administrator_invitation,
                            role: :unaffiliated, business: @business, inviter: @admin, invitee: create(:user),
                            created_at: DateTime.now - 1.day
      invitation2 = create :business_administrator_invitation,
                            role: :unaffiliated, business: @business, inviter: @admin, invitee: create(:user)

      expected_ids = [invitation2.id, invitation1.id]
      invitations = @business.pending_unaffiliated_invitations
      assert_equal expected_ids, invitations.pluck(:id)
    end

    test "can order results by created_at asc" do
      invitation1 = create :business_administrator_invitation,
                            role: :unaffiliated, business: @business, inviter: @admin, invitee: create(:user),
                            created_at: DateTime.now - 1.day
      invitation2 = create :business_administrator_invitation,
                            role: :unaffiliated, business: @business, inviter: @admin, invitee: create(:user)

      expected_ids = [invitation1.id, invitation2.id]
      invitations = @business.pending_unaffiliated_invitations(
        order_by_field: "created_at",
        order_by_direction: "asc",
      )
      assert_equal expected_ids, invitations.pluck(:id)
    end

    test "can order results by created_at desc" do
      invitation1 = create :business_administrator_invitation,
                            role: :unaffiliated, business: @business, inviter: @admin, invitee: create(:user),
                            created_at: DateTime.now - 1.day
      invitation2 = create :business_administrator_invitation,
                            role: :unaffiliated, business: @business, inviter: @admin, invitee: create(:user)

      expected_ids = [invitation2.id, invitation1.id]
      invitations = @business.pending_unaffiliated_invitations(
        order_by_field: "created_at",
        order_by_direction: "desc",
      )
      assert_equal expected_ids, invitations.pluck(:id)
    end

    test "can order results by title asc" do
      invitation1 = create :business_administrator_invitation,
                            role: :unaffiliated, business: @business, inviter: @admin, invitee: create(:user, name: "a"),
                            created_at: DateTime.now - 1.day
      invitation2 = create :business_administrator_invitation,
                            role: :unaffiliated, business: @business, inviter: @admin, invitee: create(:user, name: "b")

      expected_ids = [invitation1.id, invitation2.id]
      invitations = @business.pending_unaffiliated_invitations(
        order_by_field: "title",
        order_by_direction: "asc",
      )
      assert_equal expected_ids, invitations.pluck(:id)
    end

    test "can order results by title desc" do
      invitation1 = create :business_administrator_invitation,
                            role: :unaffiliated, business: @business, inviter: @admin, invitee: create(:user, name: "a"),
                            created_at: DateTime.now - 1.day
      invitation2 = create :business_administrator_invitation,
                            role: :unaffiliated, business: @business, inviter: @admin, invitee: create(:user, name: "b")

      expected_ids = [invitation2.id, invitation1.id]
      invitations = @business.pending_unaffiliated_invitations(
        order_by_field: "title",
        order_by_direction: "desc",
      )
      assert_equal expected_ids, invitations.pluck(:id)
    end
    test "ignores invalid ordering" do
      invitation1 = create :business_administrator_invitation,
                            role: :unaffiliated, business: @business, inviter: @admin, invitee: create(:user),
                            created_at: DateTime.now - 1.day
      invitation2 = create :business_administrator_invitation,
                            role: :unaffiliated, business: @business, inviter: @admin, invitee: create(:user)

      expected_ids = [invitation2.id, invitation1.id]
      invitations = @business.pending_unaffiliated_invitations(
        order_by_field: "invalid field",
        order_by_direction: "invalid direction",
      )
      assert_equal expected_ids, invitations.pluck(:id)
    end
  end
  context "#pending_member_invitations" do
    test "works for businesses without any orgs" do
      @business.organizations.destroy_all
      assert_equal 0, @business.pending_member_invitations.count
    end unless GitHub.single_business_environment?

    if GitHub.bypass_org_invites_enabled?
      test "is always empty when org invites are bypassed" do
        invitations = @business.pending_member_invitations
        assert_equal 0, invitations.count
      end
    else
      test "loads all pending member invitations by default" do
        invitations = @business.pending_member_invitations
        assert_equal 6, invitations.count
        assert invitations.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
        assert invitations.include?(OrganizationInvitation.find_by(invitee_id: @member2.id))
        assert invitations.include?(OrganizationInvitation.find_by(invitee_id: @member3.id))
        assert invitations.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org1))
        assert invitations.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org2))
        assert invitations.include?(OrganizationInvitation.find_by(email: "test@org2.com.net", organization: @org2))
      end

      test "orders by order_by_direction/created_at when provided" do
        T.must(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org2)).update! created_at: 2.years.ago
        T.must(OrganizationInvitation.find_by(invitee_id: @member1.id)).update! created_at: 1.year.ago
        T.must(OrganizationInvitation.find_by(invitee_id: @member2.id)).update! created_at: 6.months.ago
        T.must(OrganizationInvitation.find_by(email: "test@org2.com.net", organization: @org2)).update! created_at: 2.months.ago
        T.must(OrganizationInvitation.find_by(invitee_id: @member3.id)).update! created_at: 1.month.ago
        T.must(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org1)).update! created_at: 1.week.ago

        invitations = @business.pending_member_invitations(
          order_by_field: "created_at",
          order_by_direction: "asc",
        )

        expected = [
          OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org2),
          OrganizationInvitation.find_by(invitee_id: @member1.id),
          OrganizationInvitation.find_by(invitee_id: @member2.id),
          OrganizationInvitation.find_by(email: "test@org2.com.net", organization: @org2),
          OrganizationInvitation.find_by(invitee_id: @member3.id),
          OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org1),
        ]

        assert_equal expected, invitations

        invitations = @business.pending_member_invitations(
          order_by_field: "created_at",
          order_by_direction: "desc",
        )

        expected = [
          OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org1),
          OrganizationInvitation.find_by(invitee_id: @member3.id),
          OrganizationInvitation.find_by(email: "test@org2.com.net", organization: @org2),
          OrganizationInvitation.find_by(invitee_id: @member2.id),
          OrganizationInvitation.find_by(invitee_id: @member1.id),
          OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org2),
        ]

        assert_equal expected, invitations
      end

      test "orders by order_by_direction/title when provided" do
        invitations = @business.pending_member_invitations(
          order_by_field: "title",
          order_by_direction: "asc",
        )

        expected = [
          "Charlie",
          "member name",
          "pending-org-member2",
          "test@org1.com.net",
          "test@org1.com.net",
          "test@org2.com.net"
        ]

        assert_equal expected, invitations.map { |invite| invite.invitee&.profile&.name || invite.invitee&.login || invite.email }

        invitations = @business.pending_member_invitations(
          order_by_field: "title",
          order_by_direction: "desc",
        )

        expected = [
          "test@org2.com.net",
          "test@org1.com.net",
          "test@org1.com.net",
          "pending-org-member2",
          "member name",
          "Charlie"
        ]

        assert_equal expected, invitations.map { |invite| invite.invitee&.profile&.name || invite.invitee&.login || invite.email }
      end

      test "orders correctly even if query limit is hit when sorting by created_at" do
        Business::PendingInvitation.stub_const(:QUERY_LIMIT, 2) do
          invitations = @business.filtered_pending_invitations(
            order_by_field: "created_at",
            order_by_direction: "asc",
          )

          expected = [
            "member name",
            "test@org1.com.net"
          ]
          assert_same_elements expected, invitations.map { |invite| invite.invitee&.profile&.name || invite.invitee&.login || invite.email }
        end
      end

      test "orders correctly even if query limit is hit when sorting by title" do
        Business::PendingInvitation.stub_const(:QUERY_LIMIT, 2) do
          invitations = @business.filtered_pending_invitations(
            order_by_field: "title",
            order_by_direction: "asc",
          )

          expected = [
            "Charlie",
            "test1@test.com.net",
          ]
          assert_equal expected, invitations.map { |invite| invite.invitee&.profile&.name || invite.invitee&.login || invite.email }
        end
      end

      test "ignores invalid ordering" do
        invitations = @business.pending_member_invitations(
          order_by_field: "not a valid field",
          order_by_direction: "not a valid direction",
        )

        expected = [
          OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org1),
          OrganizationInvitation.find_by(invitee_id: @member3.id),
          OrganizationInvitation.find_by(email: "test@org2.com.net", organization: @org2),
          OrganizationInvitation.find_by(invitee_id: @member2.id),
          OrganizationInvitation.find_by(invitee_id: @member1.id),
          OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org2),
        ]

        assert_same_elements expected, invitations
      end

      test "queries for pending member invitations by organizations" do
        invitations = @business.pending_member_invitations(organizations: [@org1.login])
        assert_equal 3, invitations.count
        assert invitations.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
        assert invitations.include?(OrganizationInvitation.find_by(invitee_id: @member3.id))
        assert invitations.include?(OrganizationInvitation.find_by(email: "test@org1.com.net"))
        refute invitations.include?(OrganizationInvitation.find_by(invitee_id: @member2.id))
      end

      test "queries for pending member invitations by organizations does not find invitations for orgs outside of the business" do
        unexpected_org = create :organization
        unexpected_org.invite(@member1, inviter: unexpected_org.admins.first, invitation_source: :member)
        invitations = @business.pending_member_invitations(organizations: [unexpected_org.login])
        assert_equal 0, invitations.count
      end

      test "queries for pending member invitations by login" do
        invitations = @business.pending_member_invitations(query: "org-member")
        assert_equal 2, invitations.count
        assert invitations.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
        assert invitations.include?(OrganizationInvitation.find_by(invitee_id: @member2.id))

        invitations = @business.pending_member_invitations(query: "org-member1")
        assert_equal 1, invitations.count
        assert invitations.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
      end

      test "queries for pending member invitations by profile name" do
        invitations = @business.pending_member_invitations(query: "name")
        assert_equal 1, invitations.count
        assert invitations.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
      end

      test "can filter invitations by user login`" do
        invitations = @business.pending_member_invitations(login: @member1.login)
        assert_equal 1, invitations.count
        assert invitations.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
      end
    end
  end

  context "#pending_bundled_license_assignments" do
    if GitHub.enterprise?
      test "is always empty if in enterprise mode" do
        blas = @business.pending_bundled_license_assignments
        assert_equal 0, blas.count
      end
    else
      test "loads all pending bundled license assignments by default" do
        blas = @business.pending_bundled_license_assignments
        assert_equal 6, blas.count
        assert blas.include?(Licensing::BundledLicenseAssignment.find_by(email: "test@org1.com.net"))
        assert blas.include?(Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net"))
        assert blas.include?(Licensing::BundledLicenseAssignment.find_by(email: "test2@test.com.net"))
        assert blas.include?(Licensing::BundledLicenseAssignment.find_by(email: "test3@test.com.net"))
        assert blas.include?(Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"))
        assert blas.include?(Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"))
      end

      test "orders by order_by_direction/created_at when provided" do
        T.must(Licensing::BundledLicenseAssignment.find_by(email: "test@org1.com.net")).update! created_at: 2.years.ago
        T.must(Licensing::BundledLicenseAssignment.find_by(email: "test3@test.com.net")).update! created_at: 1.year.ago
        T.must(Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net")).update! created_at: 6.months.ago
        T.must(Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net")).update! created_at: 2.months.ago
        T.must(Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net")).update! created_at: 1.month.ago
        T.must(Licensing::BundledLicenseAssignment.find_by(email: "test2@test.com.net")).update! created_at: 1.week.ago

        blas = @business.pending_bundled_license_assignments(
          order_by_field: "created_at",
          order_by_direction: "asc",
        )

        expected = [
          Licensing::BundledLicenseAssignment.find_by(email: "test@org1.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test3@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test2@test.com.net"),
        ]

        assert_equal expected, blas

        blas = @business.pending_bundled_license_assignments(
          order_by_field: "created_at",
          order_by_direction: "desc",
        )

        expected = [
          Licensing::BundledLicenseAssignment.find_by(email: "test2@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test3@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test@org1.com.net"),
        ]

        assert_equal expected, blas
      end

      test "orders by order_by_direction/email when provided" do
        blas = @business.pending_bundled_license_assignments(
          order_by_field: "email",
          order_by_direction: "asc",
        )

        expected = [
          Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test2@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test3@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test@org1.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"),
        ]

        assert_equal expected, blas

        blas = @business.pending_bundled_license_assignments(
          order_by_field: "email",
          order_by_direction: "desc",
        )

        expected = [
          Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test@org1.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test3@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test2@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net"),
        ]

        assert_equal expected, blas
      end

      test "ignores invalid ordering" do
        blas = @business.pending_bundled_license_assignments(
          order_by_field: "not a valid field",
          order_by_direction: "not a valid direction",
        )

        expected = [
          Licensing::BundledLicenseAssignment.find_by(email: "test@org1.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test3@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"),
          Licensing::BundledLicenseAssignment.find_by(email: "test2@test.com.net"),
        ]

        assert_same_elements expected, blas
      end

      test "queries for pending bundled license assignments by email" do
        blas = @business.pending_bundled_license_assignments(query: "user")
        assert_equal 2, blas.count
        assert blas.include?(Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"))
        assert blas.include?(Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"))

        blas = @business.pending_bundled_license_assignments(query: "test1")
        assert_equal 1, blas.count
        assert blas.include?(Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net"))
      end
    end
  end

  context "#filtered_failed_invitations" do
    if GitHub.enterprise?
      test "is always empty if in enterprise mode" do
        invitations = @business.filtered_failed_invitations
        assert_equal 0, invitations.count
      end
    else
      test "loads all failed invitations by default" do
        admin_member = create(:user)
        @business.organizations.first.add_admin(admin_member)

        new_invites = []
        4.times do |num|
          member = create :user, login: "#{(4 - num)}testmember"
          invite = @business.organizations.first.invite(member, inviter: admin_member, role: :direct_member)
          invite.expire
          new_invites << invite
        end

        invitations = @business.filtered_failed_invitations
        assert_equal 4, invitations.count

        assert_equal T.unsafe(new_invites.last).id, invitations.first.original_object.id
      end

      test "loads all failed invitations title order by created_at ASC" do
        admin_member = create(:user)
        @business.organizations.first.add_admin(admin_member)

        new_invites = []
        4.times do |num|
          member = create :user, login: "#{(4 - num)}testmember"
          invite = @business.organizations.first.invite(member, inviter: admin_member, role: :direct_member)
          invite.expire
          new_invites << invite
        end

        invitations = @business.filtered_failed_invitations(order_by_field: "created_at", order_by_direction: "asc")
        assert_equal 4, invitations.count

        assert_equal T.unsafe(new_invites.first).id, invitations.first.original_object.id
      end

      test "loads all failed invitations title order by created_at DESC" do
        admin_member = create(:user)
        @business.organizations.first.add_admin(admin_member)

        new_invites = []
        4.times do |num|
          member = create :user, login: "#{(4 - num)}testmember"
          invite = @business.organizations.first.invite(member, inviter: admin_member, role: :direct_member)
          invite.expire
          new_invites << invite
        end

        invitations = @business.filtered_failed_invitations(order_by_field: "created_at", order_by_direction: "desc")
        assert_equal 4, invitations.count

        assert_equal T.unsafe(new_invites.last).id, invitations.first.original_object.id
      end

      test "loads all failed invitations order by title ASC" do
        admin_member = create(:user)
        @business.organizations.first.add_admin(admin_member)

        b_member = create :user, login: "b-member"
        b_invite = @business.organizations.first.invite(b_member, inviter: admin_member, role: :direct_member)
        b_invite.expire

        c_invite = @business.organizations.first.invite(email: "c-member@org.com", inviter: admin_member, role: :direct_member)
        c_invite.expire

        z_member = create :user, login: "a-member"
        z_member.profile_name = "Zack"
        z_member.save!
        z_invite = @business.organizations.first.invite(z_member, inviter: admin_member, role: :direct_member)
        z_invite.expire

        invitations = @business.filtered_failed_invitations(order_by_field: "title", order_by_direction: "asc")
        assert_equal 3, invitations.count

        assert_equal b_invite.id, invitations[0].original_object.id
        assert_equal c_invite.id, invitations[1].original_object.id
        assert_equal z_invite.id, invitations[2].original_object.id
      end

      test "loads all failed invitations order by title DESC" do
        admin_member = create(:user)
        @business.organizations.first.add_admin(admin_member)

        b_member = create :user, login: "b-member"
        b_invite = @business.organizations.first.invite(b_member, inviter: admin_member, role: :direct_member)
        b_invite.expire

        c_invite = @business.organizations.first.invite(email: "c-member@org.com", inviter: admin_member, role: :direct_member)
        c_invite.expire

        z_member = create :user, login: "a-member"
        z_member.profile_name = "Zack"
        z_member.save!
        z_invite = @business.organizations.first.invite(z_member, inviter: admin_member, role: :direct_member)
        z_invite.expire

        invitations = @business.filtered_failed_invitations(order_by_field: "title", order_by_direction: "desc")
        assert_equal 3, invitations.count

        assert_equal z_invite.id, invitations[0].original_object.id
        assert_equal c_invite.id, invitations[1].original_object.id
        assert_equal b_invite.id, invitations[2].original_object.id
      end

      test "queries for failed invitations by profile name" do
        admin_member = create(:user)
        @business.organizations.first.add_admin(admin_member)
        new_invites = []
        4.times do |num|
          member = create :user, login: "#{(4 - num)}testmember"
          invite = @business.organizations.first.invite(member, inviter: admin_member, role: :direct_member)
          invite.expire
          new_invites << invite
        end

        invitations = @business.filtered_failed_invitations(query: "4test")
        assert_equal 1, invitations.count
        original_objects = invitations.map(&:original_object)
        assert original_objects.include?(OrganizationInvitation.find_by(id: T.unsafe(new_invites.first).id))
      end

      test "queries for failed invitations by email" do
        admin_member = create(:user)
        @business.organizations.first.add_admin(admin_member)
        @business.organizations.second.add_admin(admin_member)

        email1 = "test@org1.com.net"
        email2 = "test@org2.com.net"

        invite1 = @business.organizations.first.invite(email: email1, inviter: admin_member, role: :direct_member)
        invite2 = @business.organizations.second.invite(email: email1, inviter: admin_member, role: :direct_member)
        invite3 = @business.organizations.second.invite(email: email2, inviter: admin_member, role: :direct_member)
        [invite1, invite2, invite3].each { |invite| invite.expire }

        invitations = @business.filtered_failed_invitations(query: "org1")

        assert_equal 2, invitations.count

        original_objects = invitations.map(&:original_object)
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org1))
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org2))
      end

      test "don't load data from other businesses" do
        outside_org = create :organization, admin: @admin
        invite = outside_org.invite(nil, email: "test@org-outside.com.net", inviter: outside_org.admins.first, invitation_source: :member)
        invite.expire

        customer_user = create :user, login: "another-customer"
        customer = create :customer, payment_method: \
          build(:paypal_payment_method, user: customer_user, customer: nil)
        create :business, :volume_licensed, owners: [@admin], organizations: [outside_org], customer: customer

        invitations = @business.filtered_failed_invitations
        assert_equal 0, invitations.count
      end
    end
  end

  context "#unique_failed_invitation_count" do
    test "returns total number of unique users with failed invitations" do
      4.times do |num|
        member = create :user, login: "testmember-#{num}"
        invite = @org1.invite(member, inviter: @admin, role: :direct_member)
        invite.expire

        invite = @org2.invite(member, inviter: @admin, role: :direct_member)
        invite.expire
      end

      unique_failed_invitations_count = @business.unique_failed_invitation_count
      failed_invitations_count = @business.failed_invitations.count

      if GitHub.bypass_org_invites_enabled?
        assert_equal 0, unique_failed_invitations_count
        assert_equal 0, failed_invitations_count
      else
        assert_equal 4, unique_failed_invitations_count
        assert_equal 8, failed_invitations_count
      end
    end
  end


  context "#filtered_pending_invitations" do
    if GitHub.enterprise?
      test "is always empty if in enterprise mode" do
        invitations = @business.filtered_pending_invitations
        assert_equal 0, invitations.count
      end
    else
      test "loads all pending invitations by default" do
        invitations = @business.filtered_pending_invitations

        assert_equal 11, invitations.count

        original_objects = invitations.map(&:original_object)
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member2.id))
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member3.id))
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org1))
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org2))
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org2.com.net", organization: @org2))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test2@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test3@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"))
      end

      test "queries for pending invitations by organization" do
        invitations = @business.filtered_pending_invitations(organizations: [@org1.login])
        assert_equal 3, invitations.count
        org_invitations = invitations.map(&:original_object)
        assert org_invitations.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
        assert org_invitations.include?(OrganizationInvitation.find_by(invitee_id: @member3.id))
        assert org_invitations.include?(OrganizationInvitation.find_by(email: "test@org1.com.net"))
        refute org_invitations.include?(OrganizationInvitation.find_by(invitee_id: @member2.id))
      end

      test "queries for pending invitations by login" do
        invitations = @business.filtered_pending_invitations(query: "org-member")

        assert_equal 2, invitations.count

        original_objects = invitations.map(&:original_object)
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member2.id))

        invitations = @business.filtered_pending_invitations(query: "org-member1")

        assert_equal 1, invitations.count

        original_objects = invitations.map(&:original_object)
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
      end

      test "queries for pending invitations by profile name" do
        @member1.profile_name = "member name"
        invitations = @business.filtered_pending_invitations(query: "member name")
        assert_equal 1, invitations.count
        original_objects = invitations.map(&:original_object)
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
      end

      test "queries for pending invitations by email" do
        invitations = @business.filtered_pending_invitations(query: "test")

        assert_equal 8, invitations.count

        original_objects = invitations.map(&:original_object)
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org1))
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org2))
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org2.com.net", organization: @org2))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test2@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test3@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"))

        invitations = @business.filtered_pending_invitations(query: "user")

        assert_equal 2, invitations.count

        original_objects = invitations.map(&:original_object)
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"))
      end

      test "filters to enterprise pending invitations" do
        invitations = @business.filtered_pending_invitations(license: "enterprise")

        assert_equal 4, invitations.count

        original_objects = invitations.map(&:original_object)
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member2.id))
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member3.id))
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org2.com.net", organization: @org2))
      end

      test "filters to enterprise with visual studio pending invitations" do
        invitations = @business.filtered_pending_invitations(license: "vss_bundle")

        assert_equal 7, invitations.count

        original_objects = invitations.map(&:original_object)
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org1))
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org2))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test2@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test3@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"))
      end

      test "shows all pending invitations if no license is chosen" do
        invitations = @business.filtered_pending_invitations(license: nil)

        assert_equal 11, invitations.count

        original_objects = invitations.map(&:original_object)
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member2.id))
        assert original_objects.include?(OrganizationInvitation.find_by(invitee_id: @member3.id))
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org1))
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org2))
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org2.com.net", organization: @org2))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test2@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test3@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"))
      end

      test "queries filtered pending invitations by email" do
        invitations = @business.filtered_pending_invitations(query: "test", license: "vss_bundle")

        assert_equal 7, invitations.count

        original_objects = invitations.map(&:original_object)
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org1))
        assert original_objects.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", organization: @org2))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test1@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test2@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "test3@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "user1@test.com.net"))
        assert original_objects.include?(Licensing::BundledLicenseAssignment.find_by(email: "user2@test.com.net"))
      end

      test "queries for pending invitations by invitation source" do
        invitations = @business.filtered_pending_invitations(invitation_source: "member")
        assert_equal 3, invitations.count
        org_invitations = invitations.map(&:original_object)
        assert org_invitations.include?(OrganizationInvitation.find_by(invitee_id: @member1.id))
        assert org_invitations.include?(OrganizationInvitation.find_by(invitee_id: @member2.id))
        assert org_invitations.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", invitation_source: :member))

        invitations = @business.filtered_pending_invitations(invitation_source: "scim")
        assert_equal 2, invitations.count
        org_invitations = invitations.map(&:original_object)
        assert org_invitations.include?(OrganizationInvitation.find_by(invitee_id: @member3.id))
        assert org_invitations.include?(OrganizationInvitation.find_by(email: "test@org1.com.net", invitation_source: :scim))
      end

      test "queries no more than expected" do
        query_counts = {
          organization_invitations: 1,
          users: 3,
          email_roles: 1,
          user_emails: 1,
          profiles: 1,
          businesses: 2
        }
        assert_max_query_count_per_table(query_counts) do
          @business.filtered_pending_invitations
        end
      end
    end
  end

  context "#unique_pending_member_invitation_count" do
    test "returns total number of unique users with pending member invitations" do
      unique_pending_member_invitations_count = @business.unique_pending_member_invitation_count
      pending_member_invitations_count = @business.pending_member_invitations.count

      if GitHub.bypass_org_invites_enabled?
        assert_equal 0, unique_pending_member_invitations_count
        assert_equal 0, pending_member_invitations_count
      else
        assert_equal 5, unique_pending_member_invitations_count
        assert_equal 6, pending_member_invitations_count
      end
    end
  end

  context "#pending_member_invitations_order" do
    unless GitHub.bypass_org_invites_enabled?
      test "default member invitation order is created_at descending" do
        invitations = @business.filtered_pending_invitations

        expected = [
          "user2@test.com.net",
          "user1@test.com.net",
          "test3@test.com.net",
          "test2@test.com.net",
          "test1@test.com.net",
          "test@org2.com.net",
          "test@org1.com.net",
          "test@org1.com.net",
          "pending-org-member2",
          "Charlie",
          "member name",
        ]
        assert_equal expected, invitations.map { |invite| invite.invitee&.profile&.name || invite.invitee&.login || invite.original_object.email }
      end

      test "can sort member invitations in ascending created order" do
        invitations = @business.filtered_pending_invitations(order_by_field: "created", order_by_direction: "asc")

        expected = [
          "member name",
          "Charlie",
          "pending-org-member2",
          "test@org1.com.net",
          "test@org1.com.net",
          "test@org2.com.net",
          "test1@test.com.net",
          "test2@test.com.net",
          "test3@test.com.net",
          "user1@test.com.net",
          "user2@test.com.net",
        ]
        assert_equal expected, invitations.map { |invite| invite.invitee&.profile&.name || invite.invitee&.login || invite.original_object.email }
      end

      test "can sort member invitations in descending created order" do
        invitations = @business.filtered_pending_invitations(order_by_field: "created", order_by_direction: "desc")

        expected = [
          "user2@test.com.net",
          "user1@test.com.net",
          "test3@test.com.net",
          "test2@test.com.net",
          "test1@test.com.net",
          "test@org2.com.net",
          "test@org1.com.net",
          "test@org1.com.net",
          "pending-org-member2",
          "Charlie",
          "member name",
        ]
        assert_equal expected, invitations.map { |invite| invite.invitee&.profile&.name || invite.invitee&.login || invite.original_object.email }
      end

      test "can sort member invitations in ascending title order" do
        invitations = @business.filtered_pending_invitations(order_by_field: "title", order_by_direction: "asc")

        expected = [
          "Charlie",
          "member name",
          "pending-org-member2",
          "test1@test.com.net",
          "test2@test.com.net",
          "test3@test.com.net",
          "test@org1.com.net",
          "test@org1.com.net",
          "test@org2.com.net",
          "user1@test.com.net",
          "user2@test.com.net"
        ]

        assert_equal expected, invitations.map { |invite| invite.invitee&.profile&.name || invite.invitee&.login || invite.original_object.email }
      end

      test "invalid sort order defaults to ascending" do
        invitations = @business.filtered_pending_invitations(order_by_field: "thatfield", order_by_direction: "descending")

        expected = [
          "user2@test.com.net",
          "user1@test.com.net",
          "test3@test.com.net",
          "test2@test.com.net",
          "test1@test.com.net",
          "test@org2.com.net",
          "test@org1.com.net",
          "test@org1.com.net",
          "pending-org-member2",
          "Charlie",
          "member name",
        ]

        assert_equal expected, invitations.map { |invite| invite.invitee&.profile&.name || invite.invitee&.login || invite.original_object.email }
      end

      test "can sort member invitations in descending title order" do
        invitations = @business.filtered_pending_invitations(order_by_field: "title", order_by_direction: "desc")

        expected = [
          "user2@test.com.net",
          "user1@test.com.net",
          "test@org2.com.net",
          "test@org1.com.net",
          "test@org1.com.net",
          "test3@test.com.net",
          "test2@test.com.net",
          "test1@test.com.net",
          "pending-org-member2",
          "member name",
          "Charlie"
        ]

        assert_equal expected, invitations.map { |invite| invite.invitee&.profile&.name || invite.invitee&.login || invite.original_object.email }
      end
    end
  end

  context "#pending_collaborator_invitations" do
    if GitHub.repo_invites_enabled?
      test "includes all repository invitations to both users and emails by default" do
        invitations = @business.pending_collaborator_invitations
        assert_equal 4, invitations.count
        expected = [
          RepositoryInvitation.find_by(invitee: @pending_collaborator1, repository: @repo1),
          RepositoryInvitation.find_by(invitee: @pending_collaborator2, repository: @repo2),
          RepositoryInvitation.find_by(invitee: @pending_collaborator3, repository: @repo1),
          RepositoryInvitation.find_by(email: "invitee@example.com", repository: @repo1),
        ]
        assert_same_elements expected, invitations
      end

      test "only returns private repository invitations when specified" do
        invitations = @business.pending_collaborator_invitations repository_visibility: :private
        assert_equal 1, invitations.count
        expected = [
          RepositoryInvitation.find_by(invitee: @pending_collaborator2, repository: @repo2),
        ]
        assert_same_elements expected, invitations
      end

      test "only returns public repository invitations when specified" do
        invitations = @business.pending_collaborator_invitations repository_visibility: :public
        assert_equal 3, invitations.count
        expected = [
          RepositoryInvitation.find_by(invitee: @pending_collaborator1, repository: @repo1),
          RepositoryInvitation.find_by(invitee: @pending_collaborator3, repository: @repo1),
          RepositoryInvitation.find_by(email: "invitee@example.com", repository: @repo1),
        ]
        assert_same_elements expected, invitations
      end

      test "returns all repository invitations when explicitly specified" do
        invitations = @business.pending_collaborator_invitations repository_visibility: :all
        assert_equal 4, invitations.count
        expected = [
          RepositoryInvitation.find_by(invitee: @pending_collaborator1, repository: @repo1),
          RepositoryInvitation.find_by(invitee: @pending_collaborator2, repository: @repo2),
          RepositoryInvitation.find_by(invitee: @pending_collaborator3, repository: @repo1),
          RepositoryInvitation.find_by(email: "invitee@example.com", repository: @repo1),
        ]
        assert_same_elements expected, invitations
      end

      test "orders by created_at desc by default" do
        T.must(RepositoryInvitation.find_by(
          invitee: @pending_collaborator1, repository: @repo1
        )).update! created_at: 2.years.ago
        T.must(RepositoryInvitation.find_by(
          invitee: @pending_collaborator2, repository: @repo2
        )).update! created_at: 1.year.ago
        T.must(RepositoryInvitation.find_by(
          invitee: @pending_collaborator3, repository: @repo1
        )).update! created_at: 1.month.ago
        T.must(RepositoryInvitation.find_by(
          email: "invitee@example.com", repository: @repo1
        )).update! created_at: 1.week.ago

        invitations = @business.pending_collaborator_invitations

        expected = [
          RepositoryInvitation.find_by(email: "invitee@example.com", repository: @repo1),
          RepositoryInvitation.find_by(invitee: @pending_collaborator3, repository: @repo1),
          RepositoryInvitation.find_by(invitee: @pending_collaborator2, repository: @repo2),
          RepositoryInvitation.find_by(invitee: @pending_collaborator1, repository: @repo1),
        ]

        assert_equal expected, invitations
      end

      test "orders by field and direction when provided" do
        T.must(RepositoryInvitation.find_by(
          invitee: @pending_collaborator1, repository: @repo1
        )).update! created_at: 2.years.ago
        T.must(RepositoryInvitation.find_by(
          invitee: @pending_collaborator2, repository: @repo2
        )).update! created_at: 1.year.ago
        T.must(RepositoryInvitation.find_by(
          invitee: @pending_collaborator3, repository: @repo1
        )).update! created_at: 1.month.ago
        T.must(RepositoryInvitation.find_by(
          email: "invitee@example.com", repository: @repo1
        )).update! created_at: 1.week.ago

        invitations = @business.pending_collaborator_invitations(
          order_by_field: "created_at",
          order_by_direction: "asc",
        )

        expected = [
          RepositoryInvitation.find_by(invitee: @pending_collaborator1, repository: @repo1),
          RepositoryInvitation.find_by(invitee: @pending_collaborator2, repository: @repo2),
          RepositoryInvitation.find_by(invitee: @pending_collaborator3, repository: @repo1),
          RepositoryInvitation.find_by(email: "invitee@example.com", repository: @repo1),
        ]

        assert_equal expected, invitations
      end

      test "ignores invalid order by field and direction" do
        T.must(RepositoryInvitation.find_by(
          invitee: @pending_collaborator1, repository: @repo1
        )).update! created_at: 2.years.ago
        T.must(RepositoryInvitation.find_by(
          invitee: @pending_collaborator2, repository: @repo2
        )).update! created_at: 1.year.ago
        T.must(RepositoryInvitation.find_by(
          invitee: @pending_collaborator3, repository: @repo1
        )).update! created_at: 1.month.ago
        T.must(RepositoryInvitation.find_by(
          email: "invitee@example.com", repository: @repo1
        )).update! created_at: 1.week.ago

        invitations = @business.pending_collaborator_invitations(
          order_by_field: "invitee_login",
          order_by_direction: "something invalid",
        )

        expected = [
          RepositoryInvitation.find_by(email: "invitee@example.com", repository: @repo1),
          RepositoryInvitation.find_by(invitee: @pending_collaborator3, repository: @repo1),
          RepositoryInvitation.find_by(invitee: @pending_collaborator2, repository: @repo2),
          RepositoryInvitation.find_by(invitee: @pending_collaborator1, repository: @repo1),
        ]

        assert_equal expected, invitations
      end

      test "queries for pending collaborator invitations by login" do
        invitations = @business.pending_collaborator_invitations(query: "example.com")
        assert_equal 1, invitations.count
        assert invitations.include?(
          RepositoryInvitation.find_by(email: "invitee@example.com", repository: @repo1)
        )

        invitations = @business.pending_collaborator_invitations(query: "pending-collaborator1")
        assert_equal 1, invitations.count
        assert invitations.include?(
          RepositoryInvitation.find_by(invitee: @pending_collaborator1, repository: @repo1)
        )
      end

      test "queries for pending collaborator invitations by profile name" do
        invitations = @business.pending_collaborator_invitations(query: "name")
        assert_equal 1, invitations.count
        assert invitations.include?(
          RepositoryInvitation.find_by(invitee: @pending_collaborator1, repository: @repo1)
        )
      end

      test "can filter invitations by user login`" do
        invitations = @business.pending_collaborator_invitations(login: @pending_collaborator1.login)
        assert_equal 1, invitations.count
        assert invitations.include?(
          RepositoryInvitation.find_by(invitee: @pending_collaborator1, repository: @repo1)
        )
      end

      test "includes collaborator invitations in forked private repositories" do
        @org1.allow_private_repository_forking(actor: @org1.admins.first, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
        forker = create(:user)
        external_collaborator = create(:user)
        @org1.add_member(forker)
        repo = create(:private_repository, owner: @org1)
        forked_repo = create(:fork_repository, forker: forker, fork_repo: repo)

        RepositoryInvitation.invite_to_repo(external_collaborator, forker, forked_repo)
        RepositoryInvitation.invite_to_repo_by_email("outsider_email@example.com", forker, forked_repo)
        invitations = @business.pending_collaborator_invitations(repository_visibility: :private)
        assert_equal 3, invitations.count
        expected = [
          RepositoryInvitation.find_by(invitee: @pending_collaborator2, repository: @repo2),
          RepositoryInvitation.find_by(invitee: external_collaborator, repository: forked_repo),
          RepositoryInvitation.find_by(email: "outsider_email@example.com", repository: forked_repo)
        ]
        assert_same_elements expected, invitations.to_a
      end

      test "excludes collaborator invitations in forked private repositories when specified" do
        @org1.allow_private_repository_forking(actor: @org1.admins.first, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
        forker = create(:user)
        external_collaborator = create(:user)
        @org1.add_member(forker)
        repo = create(:private_repository, owner: @org1)
        forked_repo = create(:fork_repository, forker: forker, fork_repo: repo)

        RepositoryInvitation.invite_to_repo(external_collaborator, forker, forked_repo)
        RepositoryInvitation.invite_to_repo_by_email("outsider_email@example.com", forker, forked_repo)
        invitations = @business.pending_collaborator_invitations(
          repository_visibility: :private,
          include_forks: false
        )

        assert_equal 1, invitations.count
        expected = [
          RepositoryInvitation.find_by(invitee: @pending_collaborator2, repository: @repo2),
        ]
        assert_same_elements expected, invitations
      end
    else
      test "is always empty when repo invites are not available" do
        assert_empty @business.pending_collaborator_invitations
      end
    end
  end

  context "#user_accounts_with_only_emails" do
    if GitHub.single_business_environment?
      test "always returns an empty array" do
        assert_empty @business.user_accounts_with_only_emails
      end
    else
      test "returns the business user accounts that don't have a user set but do have a primary email from an enterprise installation" do
        enterprise_installation1 = create(:enterprise_installation, owner: @business)
        enterprise_installation2 = create(:enterprise_installation, owner: @business)

        business_user_account_with_user_id = create(:business_user_account, business: @business, user: create(:user))
        enterprise_installation_user_account_with_user_id = create(
          :enterprise_installation_user_account,
          business_user_account: business_user_account_with_user_id,
          enterprise_installation: enterprise_installation1
        )
        create(
          :enterprise_installation_user_account_email,
          enterprise_installation_user_account: enterprise_installation_user_account_with_user_id,
          email: "example1@example.com",
          primary: true
        )

        business_user_account_with_no_emails = create(:business_user_account, business: @business, user: create(:user))
        _enterprise_installation_user_account_with_no_emails = create(
          :enterprise_installation_user_account,
          business_user_account: business_user_account_with_no_emails,
          enterprise_installation: enterprise_installation1
        )

        business_user_account_with_primary_emails = create(:business_user_account, business: @business, user: nil)
        enterprise_installation_user_account_with_email1 = create(
          :enterprise_installation_user_account,
          business_user_account: business_user_account_with_primary_emails,
          enterprise_installation: enterprise_installation1
        )
        create(
          :enterprise_installation_user_account_email,
          enterprise_installation_user_account: enterprise_installation_user_account_with_email1,
          email: "example2@example.com",
          primary: true
        )
        enterprise_installation_user_account_with_email2 = create(
          :enterprise_installation_user_account,
          business_user_account: business_user_account_with_primary_emails,
          enterprise_installation: enterprise_installation2
        )
        create(
          :enterprise_installation_user_account_email,
          enterprise_installation_user_account: enterprise_installation_user_account_with_email2,
          email: "example3@example.com",
          primary: true
        )

        business_user_account_with_no_primary_emails = create(:business_user_account, business: @business, user: nil)
        enterprise_installation_user_account_with_no_primary_email = create(
          :enterprise_installation_user_account,
          business_user_account: business_user_account_with_no_primary_emails,
          enterprise_installation: enterprise_installation1
        )
        create(
          :enterprise_installation_user_account_email,
          enterprise_installation_user_account: enterprise_installation_user_account_with_no_primary_email,
          email: "example3@example.com",
          primary: false
        )

        assert_same_elements(
          [business_user_account_with_primary_emails],
          @business.user_accounts_with_only_emails
        )
      end
    end
  end

  context "#enterprise_installation_user_ids" do
    if GitHub.single_business_environment?
      test "always returns an empty array" do
        assert_empty @business.enterprise_installation_user_ids
      end
    else
      test "returns the user IDs from the business user accounts that have enterprise installation user accounts" do
        business = create(:business)
        enterprise_installation = create(:enterprise_installation, owner: business)

        business_user_account_with_user_id_and_enterprise_installation_user_account = create(:business_user_account, business: business, user: create(:user))
        create(
          :enterprise_installation_user_account,
          business_user_account: business_user_account_with_user_id_and_enterprise_installation_user_account,
          enterprise_installation: enterprise_installation
        )

        _business_user_account_with_user_id_no_enterprise_installation = create(:business_user_account, business: business, user: create(:user))

        _business_user_account_with_no_user_id = create(:business_user_account, business: business, user: nil)

        business.reload # make business aware of enterprise installations

        assert_same_elements(
          [business_user_account_with_user_id_and_enterprise_installation_user_account.user_id],
          business.enterprise_installation_user_ids
        )
      end
    end
  end

  context "#suspended_members" do
    test "returns nil for normal dotcom business and GHES" do
      assert_nil @business.suspended_members
    end
  end

  context "#suspended_member_ids" do
    test "returns nil for normal dotcom business and GHES" do
      assert_nil @business.suspended_member_ids
    end
  end

  context "#enterprise_installations_for" do
    unless GitHub.single_business_environment?
      test "returns nothing if `member` is not a User or BusinessUserAccount" do
        assert_same_elements [], @second_business.enterprise_installations_for(member: nil)
      end

      test "returns the enterprise installations for a BusinessUserAccount" do
        business_user_account, installation, installation2 = setup_user_enterprise_installations(@second_business, @second_org, @second_member)
        enterprise_installations = @second_business.enterprise_installations_for(member: @second_member)
        assert_equal 2, enterprise_installations.size
      end

      test "returns the enterprise installations for a User with a BusinessUserAccount" do
        business_user_account, installation, installation2 = setup_user_enterprise_installations(@second_business, @second_org, @second_member)
        enterprise_installations = @second_business.enterprise_installations_for(member: business_user_account.user)
        assert_equal 2, enterprise_installations.size
      end

      test "returns nothing for a BusinessUserAccount with no installations" do
        other_member = create :user
        @second_org.add_member other_member

        # Create installations on the business
        business_user_account, installation, installation2 = setup_user_enterprise_installations(@second_business, @second_org, @second_member)

        # Check for installations on the other member
        other_business_user_account = @second_business.user_accounts.find_by!(user_id: other_member.id)
        assert_same_elements [], @second_business.enterprise_installations_for(member: other_business_user_account)
      end

      test "returns nothing for a User account looking at a different business" do
        other_org = create :organization, plan: GitHub::Plan.business_plus, seats: 10, admin: @second_admin
        other_business = create :business, owners: [@second_admin]

        # Add enterprise installations to the account
        business_user_account, installation, installation2 = setup_user_enterprise_installations(@second_business, @second_org, @second_admin)

        # Try to view member's installations using wrong business
        enterprise_installations = other_business.enterprise_installations_for(member: @second_admin)
        assert_equal 0, enterprise_installations.size
      end
    end
  end

  context "#enterprise_organizations_for" do
    if GitHub.single_business_environment?
      test "returns the organization memberships which the viewer has privileges to see" do
        GitHub::Enterprise.ensure_business!
        org1 = create :organization
        org2 = create :organization
        org2.publicize_member(org2.admin)
        org1.add_member(org2.admin)
        business = GitHub.global_business

        assert_same_elements [org1, org2], business.enterprise_organizations_for(member: org2.admin, viewer: org1.admin)
        assert_same_elements [org1], business.enterprise_organizations_for(member: org1.admin, viewer: org2.admin)
      end
    else
      test "returns nothing if `member` is not a User or BusinessUserAccount" do
        business = create :business, :volume_licensed
        assert_same_elements [], business.enterprise_organizations_for(member: nil, viewer: business.admins.first)
      end

      test "returns the enterprise organizations for a BusinessUserAccount" do
        business = create :business
        org = create :organization
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) { business.add_organization(org) }
        business_user_account = business.user_accounts.find_by!(user: org.admin)
        # view = build_view(business: business)
        assert_same_elements [org], business.enterprise_organizations_for(member: business_user_account, viewer: business.admins.first)
      end

      test "returns the enterprise organizations for the user's BusinessUserAccount" do
        org = create :organization
        business = create :business, :volume_licensed, organizations: [org]
        assert_same_elements [org], business.enterprise_organizations_for(member: org.admin, viewer: business.admins.first)
      end

      test "returns nothing if the User has no BusinessUserAccount for the business" do
        business = create :business, :volume_licensed
        user = create :user
        assert_same_elements [], business.enterprise_organizations_for(member: user, viewer: business.admins.first)
      end
    end
  end
end

class GHESWithSCIMPeopleDependencyTest < GitHub::TestCase
  include SCIMBusinessPeopleDependencySharedTests
  include AuthenticationHelpers::SAML

  fixtures do
    setup_saml_auth_mode(with_scim: true)

    @enterprise = create(:global_business)
    @first_owner = @enterprise.owners.first

    @admin = create(:ghes_scim_user, business: @enterprise, login: "saml-scim-admin")
    @admin.grant_site_admin_access("saml/scim single sign-on administrator promotion")
    @enterprise.add_owner(@admin, actor: nil, send_email_notification: false)

    @saml_mapped_user = create(:user_saml_mapping).user

    @user = create(:ghes_scim_user, business: @enterprise, login: "saml-scim-user")
    @local_user = create(:user, business: @enterprise, login: "local-user")

    provider = create :business_saml_provider, business: @enterprise
    provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")

    # suspended users
    @suspended1 = create :ghes_scim_user, business: @enterprise, login: "suspended-user1"
    @suspended2 = create :ghes_scim_user, business: @enterprise, login: "suspended2"
    @suspended_other = create :ghes_scim_user, business: @enterprise, login: "other-suspended"

    @suspended1.profile_name = "suspended member 1"
    @suspended1.save!

    @suspended1.suspend("test supsension")
    @suspended2.suspend("test supsension")
    @suspended_other.suspend("test supsension")

    @suspended_expected = [@suspended1, @suspended2, @suspended_other]
    @expected_login = %w[other-suspended suspended-user1 suspended2]
    @expected_login_desc = %w[suspended2 suspended-user1 other-suspended]
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end

  context "account_type filter" do
    test "filters by local auth type for members" do
      assert_empty @local_user.external_identities
      assert_nil @local_user.saml_mapping

      assert_empty @first_owner.external_identities
      assert_nil @first_owner.saml_mapping

      members = @enterprise.filtered_members(@admin, account_type: :built_in)
      # first root site admin will always be included
      assert_equal 2, members.count
      assert_same_elements members, [@local_user, @first_owner]

      # find the root site admin
      members = @enterprise.filtered_members(@admin, role: "enterprise_owner", account_type: :built_in)
      assert_equal 1, members.count
      refute_includes members, @local_user
      assert_includes members, @first_owner
    end

    test "filters by SAML JIT provisioned for members" do
      assert_empty @saml_mapped_user.external_identities
      refute_nil @saml_mapped_user.saml_mapping

      members = @enterprise.filtered_members(@admin, account_type: :saml_linked)
      assert_equal 1, members.count
      assert_same_elements members, [@saml_mapped_user]
    end

    test "filters by SCIM provisioned for members" do
      refute_empty @admin.external_identities
      refute_empty @user.external_identities

      members = @enterprise.filtered_members(@admin, account_type: :saml_and_scim_linked)
      assert_equal 2, members.count
      assert_same_elements members, [@admin, @user]
    end

    test "filters correctly for SCIM provisioned users that used to be SAML JIT provisioned" do
      create(:external_identity, user: @saml_mapped_user)

      refute_nil @saml_mapped_user.saml_mapping
      refute_empty @saml_mapped_user.external_identities

      members = @enterprise.filtered_members(@admin, account_type: :saml_and_scim_linked)
      assert_equal 3, members.count
      assert_same_elements members, [@admin, @user, @saml_mapped_user]
    end
  end
end if GitHub.single_business_environment?

class EnterpriseManagedBusinessPeopleDependencyTest < GitHub::TestCase
  include SCIMBusinessPeopleDependencySharedTests

  fixtures do
    @enterprise_user_1 = create :emu, :owner, login: "enterprise-user-1"
    @enterprise = @enterprise_user_1.enterprise_managed_business
    @owner = @enterprise.find_first_emu_owner

    # second EMU enterprise
    @enterprise_user_2 = create :emu, :owner, login: "enterprise-user-2"
    @enterprise_2 = @enterprise_user_2.enterprise_managed_business

    # org owners
    @org_admin_alpha = create :emu, business: @enterprise, login: "org-admin-alpha"
    @org_admin_bravo = create :emu, business: @enterprise, login: "org-admin-bravo"

    # orgs
    @org_alpha = create(:organization, business: @enterprise, admin: @org_admin_alpha)
    @org_bravo = create(:organization, business: @enterprise, admin: @org_admin_bravo)

    # org members
    @org_member_alpha = create :emu, business: @enterprise, login: "org-member-alpha"
    @org_member_bravo = create :emu, business: @enterprise, login: "org-member-bravo"

    @org_alpha.add_member(@org_member_alpha)
    @org_bravo.add_member(@org_member_bravo)

    # enterprise members
    @unaffiliated_user_1 = create :emu, business: @enterprise, login: "enterprise-user-2"
    @unaffiliated_user_2 = create :emu, business: @enterprise, login: "enterprise-user-3"

    @unaffiliated_user_2.profile_name = "enterprise user 3"
    @unaffiliated_user_2.save!

    # Enterprise Installation Accounts
    # Enterprise installation user with GHEC org membership
    @enterprise_installation_user = create :emu, business: @enterprise, login: "installation-user"
    @enterprise_installation = create(:enterprise_installation, owner: @enterprise)

    create :enterprise_installation_user_account, \
      enterprise_installation: @enterprise_installation,
      profile_name: @enterprise_installation_user.login,
      business_user_account: @enterprise.user_accounts.find_by(user: @enterprise_installation_user)

    @org_alpha.add_member(@enterprise_installation_user)

    # Enterprise installation in 2nd enterprise
    @enterprise_installation_user_2 = create :emu, business: @enterprise_2, login: "installation-user-2"
    @enterprise_installation_2 = create(:enterprise_installation, owner: @enterprise_2)

    create :enterprise_installation_user_account, \
      enterprise_installation: @enterprise_installation_2,
      profile_name: @enterprise_installation_user_2.login,
      business_user_account: @enterprise_2.user_accounts.find_by(user: @enterprise_installation_user_2)

    # Enterprise installation user without GHEC org membership
    @unaffiliated_enterprise_installation_user = create :emu, business: @enterprise,
      login: "unaffiliated-installation-user"

    create :enterprise_installation_user_account, \
      enterprise_installation: @enterprise_installation,
      profile_name: @unaffiliated_enterprise_installation_user.login,
      business_user_account: @enterprise.user_accounts.find_by(user: @unaffiliated_enterprise_installation_user)

    # guest collaborators
    @guest_collaborator_org_member = create :emu, :guest_collaborator, business: @enterprise, login: "guest-collaborator-1"
    @guest_collaborator_unaffiliated = create :emu, :guest_collaborator, business: @enterprise, login: "guest-collaborator-2"

    @org_alpha.add_member(@guest_collaborator_org_member)

    # all member ids for test comparisons
    @expected_all_member_ids = [
      @owner,
      @enterprise_user_1,
      @guest_collaborator_org_member,
      @guest_collaborator_unaffiliated,
      @unaffiliated_user_1,
      @unaffiliated_user_2,
      @org_member_alpha,
      @org_member_bravo,
      @org_admin_alpha,
      @org_admin_bravo,
      @enterprise_installation_user,
      @unaffiliated_enterprise_installation_user
    ].map(&:id)

    # scim suspended users with either be disabled or will not have an external identity record
    @suspended1 = create :emu, login: "suspended-user1", business: @enterprise
    @suspended2 = create :emu, login: "suspended2", business: @enterprise
    @suspended_other = create :emu, login: "other-suspended", business: @enterprise

    @suspended1.profile_name = "suspended member 1"
    @suspended1.save!

    @suspended1.external_identities.first.disable
    @suspended2.external_identities.first.disable
    @suspended_other.external_identities.first.destroy

    @shortcode = @enterprise.shortcode

    @suspended_expected = [@suspended1, @suspended2, @suspended_other]
    @expected_login = ["other-suspended_#{@shortcode}", "suspended-user1_#{@shortcode}", "suspended2_#{@shortcode}"]
    @expected_login_desc = ["suspended2_#{@shortcode}", "suspended-user1_#{@shortcode}", "other-suspended_#{@shortcode}"]

    perform_enqueued_jobs only: [BusinessUserAccountCreateForOrganizationJob]
  end

  setup do
    BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise.id)
    BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise_2.id)
  end

  test "ordered and paginated members with batched_scope" do
    members = @enterprise.filtered_members(@enterprise_user_1, batched_scope: true, batch_size: 5)
    expected = [
      @enterprise_user_1,
      @unaffiliated_user_1,
      @unaffiliated_user_2,
      @enterprise_installation_user,
      @org_admin_alpha,
      @org_admin_bravo,
      @org_member_bravo,
      @org_member_alpha,
      @guest_collaborator_org_member,
      @guest_collaborator_unaffiliated,
      @owner,
      @unaffiliated_enterprise_installation_user
    ].map(&:login).sort
    assert_equal expected.slice(0, 5), members.paginate(page: 1, per_page: 5).map(&:login)
    assert_equal expected.slice(5, 5), members.paginate(page: 2, per_page: 5).map(&:login)
    assert_equal expected, members.paginate(page: 1, per_page: 20).map(&:login)
  end

  context "#pending_collaborator_invitations" do
    test "no pending collaborator invitations for EMUs" do
      invitations = @enterprise.pending_collaborator_invitations
      assert_equal 0, invitations.count
    end
  end

  context "#pending_member_invitations" do
    test "no pending member invitations for EMUs" do
      invitations = @enterprise.pending_member_invitations
      assert_equal 0, invitations.count
    end
  end

  context "#filtered_members" do
    test "shows all users with business_user_account when no filters passed" do
      members = @enterprise.filtered_members(@owner)

      assert_same_elements members.map(&:user_id), @expected_all_member_ids
    end

    test "does not show suspended users" do
      suspended_user = create :emu, business: @enterprise, login: "suspended-user"
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise.id)

      members = @enterprise.filtered_members(@owner)
      assert_same_elements  @expected_all_member_ids + [suspended_user.id], members.map(&:user_id)

      suspended_user.external_identities.first.disable
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise.id)

      members = @enterprise.filtered_members(@owner)
      assert_same_elements  @expected_all_member_ids, members.map(&:user_id)
    end

    test "treats users without external identity record as suspended" do
      suspended_user = create :emu, business: @enterprise, login: "suspended-user"
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise.id)

      members = @enterprise.filtered_members(@owner)
      assert_same_elements  @expected_all_member_ids + [suspended_user.id], members.map(&:user_id)

      suspended_user.external_identities.first.destroy
      suspended_user.unsuspend("for testing only")
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise.id)

      members = @enterprise.filtered_members(@owner)
      assert_same_elements  @expected_all_member_ids, members.map(&:user_id)
    end

    test "EMU business shows spammy members to all viewers" do
      spammer = create :emu, business: @enterprise, spammy: true
      @org_alpha.add_member(spammer)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise.id)

      expected_member_ids = @expected_all_member_ids + [spammer.id]

      members = @enterprise.filtered_members(@enterprise_user_1)

      assert_same_elements members.map(&:user_id), expected_member_ids
    end

    test "queries for users by login" do
      members = @enterprise.filtered_members(@owner, query: "enterprise-user")

      expected_member_ids = [@enterprise_user_1.id, @unaffiliated_user_1.id, @unaffiliated_user_2.id]

      assert_same_elements members.map(&:user_id), expected_member_ids

      members = @enterprise.filtered_members(@owner, query: "enterprise-user-1")

      assert_equal 1, members.count
      assert_equal members.first.user_id, @enterprise_user_1.id
    end

    test "does not query suspended users by login" do
      suspended_user = create :emu, business: @enterprise, login: "suspended-user"
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise.id)

      members = @enterprise.filtered_members(@owner, query: "suspended-user")
      assert_same_elements [suspended_user.id], members.map(&:user_id)

      suspended_user.external_identities.first.disable
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise.id)

      members = @enterprise.filtered_members(@owner, query: "suspended-user")

      assert_equal 0, members.count
    end

    test "queries for members by profile name" do
      members = @enterprise.filtered_members(@owner, query: "enterprise user")

      assert_equal 1, members.count
      assert_equal members.first.user_id, @unaffiliated_user_2.id
    end

    test "filters role to organization owners" do
      members = @enterprise.filtered_members(@owner, role: "owner")

      expected_member_ids = [@org_admin_alpha.id, @org_admin_bravo.id]

      assert_same_elements members.map(&:user_id), expected_member_ids
    end

    test "does not query suspended users when filters role to organization owners" do
      suspended_user = create :emu, business: @enterprise, login: "suspended-user"
      @org_alpha.add_admin(suspended_user, adder: @owner)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise.id)

      members = @enterprise.filtered_members(@owner, role: "owner")
      assert_includes members.map(&:user_id), suspended_user.id

      suspended_user.external_identities.first.disable
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise.id)

      members = @enterprise.filtered_members(@owner, role: "owner")
      refute_includes members.map(&:user_id), suspended_user.id
    end

    test "filters role to organization members" do
      members = @enterprise.filtered_members(@owner, role: "member")

      expected_member_ids = [
        @org_member_alpha.id,
        @org_member_bravo.id,
        @guest_collaborator_org_member.id,
        @enterprise_installation_user.id,
        @unaffiliated_enterprise_installation_user.id # Included because they are members from enterprise installation
      ]

      assert_same_elements members.pluck(:user_id), expected_member_ids
    end

    test "filters role to organization members with batching" do
      members = @enterprise.filtered_members(@owner, role: "member", batched_scope: true, batch_size: 3)

      expected_member_ids = [
        @org_member_alpha.id,
        @org_member_bravo.id,
        @guest_collaborator_org_member.id,
        @enterprise_installation_user.id,
        @unaffiliated_enterprise_installation_user.id # Included because they are members from enterprise installation
      ]

      assert_same_elements members.pluck(:user_id), expected_member_ids
    end

    test "does not query suspended users when filters role to organization members" do
      suspended_user = create :emu, business: @enterprise, login: "suspended-user"
      @org_alpha.add_member(suspended_user)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise.id)

      members = @enterprise.filtered_members(@owner, role: "member")

      assert_includes members.map(&:user_id), suspended_user.id

      suspended_user.external_identities.first.disable
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @enterprise.id)

      members = @enterprise.filtered_members(@owner, role: "member")
      refute_includes members.map(&:user_id), suspended_user.id
    end

    test "shows all members if no deployment filter is chosen" do
      members = @enterprise.filtered_members(@owner, deployment: nil)

      assert_same_elements members.map(&:user_id), @expected_all_member_ids
    end

    test "shows all members if cloud deployment filter is chosen" do
      members = @enterprise.filtered_members(@owner, deployment: "cloud")

      assert_same_elements members.map(&:user_id), @expected_all_member_ids
    end

    test "shows server members if server deployment filter is chosen" do
      members = @enterprise.filtered_members(@owner, deployment: "server")

      expected_member_ids = [@enterprise_installation_user.id, @unaffiliated_enterprise_installation_user.id]

      assert_same_elements members.pluck(:user_id), expected_member_ids
    end

    test "shows server members if server deployment filter is chosen with batched_scope" do
      members = @enterprise.filtered_members(@owner, deployment: "server", batched_scope: true)

      expected_member_ids = [@enterprise_installation_user.id, @unaffiliated_enterprise_installation_user.id]

      assert_same_elements members.pluck(:user_id), expected_member_ids
    end

    test "shows org members when specified in org_logins" do
      members = @enterprise.filtered_members(@owner, organization_logins: [@org_alpha.login])

      expected_member_ids = [@org_admin_alpha.id, @org_member_alpha.id, @guest_collaborator_org_member.id, @enterprise_installation_user.id]

      assert_same_elements members.map(&:user_id), expected_member_ids

      members = @enterprise.filtered_members(@owner, organization_logins: [@org_alpha.login, @org_bravo.login])

      expected_member_ids = [
        @org_admin_alpha.id,
        @org_member_alpha.id,
        @org_admin_bravo.id,
        @org_member_bravo.id,
        @guest_collaborator_org_member.id,
        @enterprise_installation_user.id
      ]

      assert_same_elements members.map(&:user_id), expected_member_ids
    end

    test "returns all members when viewing as non-admin by default" do
      members = @enterprise.filtered_members(@enterprise_user_1)

      assert_same_elements members.map(&:user_id), @expected_all_member_ids
    end

    test "shows unaffiliated emus when role is specified" do
      unaffiliated_emus = @enterprise.filtered_members(@owner, role: "unaffiliated")

      assert_same_elements unaffiliated_emus.pluck(:user_id), [
        @unaffiliated_user_1,
        @unaffiliated_user_2,
        @unaffiliated_enterprise_installation_user,
        @guest_collaborator_unaffiliated
      ].pluck(:id)

      # This does not show @enterprise_installation_user since they have an org membership on GHEC
      refute_includes unaffiliated_emus.pluck(:user_id), @enterprise_installation_user.id
    end

    test "does not return any users if role is 'unaffiliated' but organizations are specified" do
      assert_empty @enterprise.filtered_members(@owner, role: "unaffiliated", organization_logins: [@org_alpha.login])
    end

    test "does not return any admin user when role is 'unaffiliated'" do
      users = @enterprise.filtered_members(@owner, role: "unaffiliated")
      refute_includes users.pluck(:user_id), @owner.id
    end

    test "ignores role:unaffiliated if business is not EMU-enabled, returns all members" do
      disable_feature_flag(:unaffiliated_user_accounts)
      disable_feature_flag(:enterprise_teams_migrate_from_cfb)
      disable_feature_flag(:business_user_account_filtered_members)
      non_emu_business_owner = create :user, login: "non-emu-business-owner"
      non_emu_business = create :business, slug: "non-emu-business", owners: [non_emu_business_owner]
      random_org_admin = create :user, login: "random-org-admin"
      random_org = create :organization, business: non_emu_business, login: "random-org", admins: [random_org_admin]
      non_emu_business.reload

      assert_same_elements non_emu_business.filtered_members(non_emu_business_owner, role: "unaffiliated"), non_emu_business.filtered_members(non_emu_business_owner)
    end

    test "shows members with copilot license assigned" do
      assignment = create(:copilot_seat_assignment, :enterprise_team, team_name: "team1", member_count: 1)
      business = assignment.owner
      admin = business.owners.first
      ent_team = assignment.assignable
      unaffiliated2 = create :emu, business: business, login: "enterprise-user-3"
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: business.id)
      unaffiliated = business.user_accounts.exclusive_unaffiliated_role.first.user
      EnterpriseTeamAssignment.create!(enterprise_team: ent_team, assignment_type: "copilot")
      Copilot::Business.new(business).assign([ent_team], admin)
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: business.id)
      members = if GitHub.flipper[:business_user_account_filtered_members].enabled?
        business.filtered_members(admin, license: "copilot", include_unaffiliated: true)
      else
        business.filtered_members(admin, license: "copilot", role: "unaffiliated")
      end
      assert_equal 1, members.count
      assert_includes members.pluck(:user_id), unaffiliated.id
      if GitHub.flipper[:business_user_account_filtered_members].enabled?
        members = business.filtered_members(admin, license: "no_copilot", include_unaffiliated: true)
        assert_equal 3, members.count
        assert_includes members.pluck(:user_id), admin.id
        assert_includes members.pluck(:user_id), unaffiliated2.id
      else
        members = business.filtered_members(admin, license: "no_copilot", role: "unaffiliated")
        assert_equal 1, members.count
        assert_includes members.pluck(:user_id), unaffiliated2.id
      end
    end

    test "filters by guest collaborator role" do
      members = @enterprise.filtered_members(@owner, role: "guest_collaborator")
      assert_same_elements members.pluck(:user_id), [@guest_collaborator_org_member, @guest_collaborator_unaffiliated].map(&:id)
    end

    test "filters by guest collaborator role by org" do
      members = @enterprise.filtered_members(@owner, role: "guest_collaborator", organization_logins: [@org_alpha.login])
      assert_same_elements members.pluck(:user_id), [@guest_collaborator_org_member].map(&:id)
    end

    test "ignores role:guest_collaborator if business is not EMU-enabled, returns all members" do
      non_emu_business_owner = create :user, login: "non-emu-business-owner"
      non_emu_business = create :business, slug: "non-emu-business", owners: [non_emu_business_owner]
      random_org_admin = create :user, login: "random-org-admin"
      random_org = create :organization, business: non_emu_business, login: "random-org", admins: [random_org_admin]
      non_emu_business.reload

      assert_same_elements non_emu_business.filtered_members(non_emu_business_owner, role: "guest_collaborator"), non_emu_business.filtered_members(non_emu_business_owner)
    end
  end

  context "#all_guest_collaborators" do
    test "includes ids for all guest collaborators" do
      member_ids = @enterprise.all_guest_collaborators.pluck(:id)
      assert_equal [@guest_collaborator_org_member, @guest_collaborator_unaffiliated].map(&:id).sort, member_ids.sort
    end

    test "returns the same guest collaborator role results as #filtered_members" do
      assert_equal @enterprise.filtered_members(@owner, role: "guest_collaborator").pluck(:user_id).sort, @enterprise.all_guest_collaborators.pluck(:id).sort
    end
  end
end unless GitHub.single_business_environment?
