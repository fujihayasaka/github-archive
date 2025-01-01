# typed: true
# frozen_string_literal: true

require "test_helper"

class UserBusinessDependencyTest < GitHub::TestCase
  fixtures do
    # Allow creation of multiple businesses for these tests, regardless of
    # whether running in single global business mode or not.
    GitHub.stubs(:single_business_environment?).returns(false)
    @business_admin = create :user
    @business_1 = create :business, owners: [@business_admin]
    @business_2 = create :business, owners: [@business_admin]
    @business_3 = create :business, owners: [@business_admin]
    @unowned_business = create :business

    @billing_manager = create :user
    @business_1.billing.add_manager @billing_manager, actor: @business_admin
    @business_3.billing.add_manager @billing_manager, actor: @business_admin

    @org_member = create :user
    @org_support_member = create :user
    @org_admin = create :user
    @org = create :organization, admin: @org_admin
    @org.add_member @org_member
    @org.add_member @org_support_member
    @business_4 = create :business, organizations: [@org]
    @business_4.add_support_entitlee(@org_support_member, actor: @org_admin)

    unless GitHub.enterprise?
      @emu_business = create(:business, :enterprise_managed)
      @emu_owner = @emu_business.owners.first
      @emu_user = create(:emu, business: @emu_business)

      @emu_org = create :organization, business: @emu_business, admin: @emu_owner
      @emu_org_internal_repo = create(:internal_repository, owner: @emu_org)
      @guest_collaborator = create(:emu, :guest_collaborator, business: @emu_business)
      @emu_org.add_member @guest_collaborator
    end
  end

  context "#in_a_sales_managed_business?" do
    test "returns false for an individual user" do
      user = build :user
      refute user.in_a_sales_managed_business?
    end

    test "returns false for an organization with no business" do
      org = build :organization
      refute org.in_a_sales_managed_business?
    end

    test "returns false for an organization which is part of a self-serve business" do
      org = create :organization
      build(:business).organizations << org
      org.reload

      refute org.in_a_sales_managed_business?
    end

    test "returns true for an organization which is part of a non-self-serve business" do
      org = create :organization
      build(:business, can_self_serve: false).organizations << org
      org.reload

      refute org.in_a_sales_managed_business?
    end
  end

  context "#businesses" do
    test "includes businesses in which the user is an admin when membership_type: :admin" do
      businesses = @business_admin.businesses membership_type: :admin
      async_businesses = @business_admin.async_businesses(membership_type: :admin).sync

      assert_same_elements businesses, async_businesses, "Synchronous and Asynchronous versions of this method should return the same thing."
      assert_same_elements [@business_1, @business_2, @business_3], businesses
    end

    test "includes businesses in which the user is a billing manager when membership_type: :billing_manager" do
      businesses = @billing_manager.businesses membership_type: :billing_manager
      async_businesses = @billing_manager.async_businesses(membership_type: :billing_manager).sync

      assert_same_elements businesses, async_businesses, "Synchronous and Asynchronous versions of this method should return the same thing."
      assert_same_elements [@business_1, @business_3], businesses
    end

    test "includes businesses in which the user is a support entitlee and a member when membership_type: :support_entitled" do
      assert_same_elements [@business_4], @org_support_member.businesses(membership_type: :support_entitled)
      assert_equal [], @org_member.businesses(membership_type: :support_entitled)
    end


    test "includes businesses that own an org when user is org admin and membership_type: :org_membership" do
      businesses = @org_admin.businesses membership_type: :org_membership
      async_businesses = @org_admin.async_businesses(membership_type: :org_membership).sync

      assert_same_elements businesses, async_businesses, "Synchronous and Asynchronous versions of this method should return the same thing."
      assert_same_elements [@business_4], businesses
    end

    test "includes businesses that own an org when user is org member and membership_type: :org_membership" do
      businesses = @org_member.businesses membership_type: :org_membership
      async_businesses = @org_member.async_businesses(membership_type: :org_membership).sync

      assert_same_elements businesses, async_businesses, "Synchronous and Asynchronous versions of this method should return the same thing."
      assert_same_elements [@business_4], businesses
    end

    test "includes businesses where user is an admin, billing manager, or org member/admin with membership_type: :all and valid_license: false", skip_enterprise: true do
      user = create :user
      @business_1.add_owner user, actor: @business_admin
      @business_2.billing.add_manager user, actor: @billing_admin
      @org.add_member user
      org_2 = create :organization, admin: user
      business_5 = create :business, organizations: [org_2]

      businesses = user.businesses
      async_businesses = user.async_businesses

      assert_same_elements [@business_1, @business_2, @business_4, business_5], businesses
      assert_same_elements [@business_1, @business_2, @business_4, business_5], async_businesses.sync
    end

    test "excludes businesses where user is billing manager but not org member with membership_type: :all and valid_license: true", skip_enterprise: true do
      enable_feature_flag(:bus_ids_exclude_billing_manager_valid_license)
      businesses = @billing_manager.businesses membership_type: :all, valid_license: true
      async_businesses = @billing_manager.async_businesses(membership_type: :all, valid_license: true).sync

      assert_same_elements businesses, async_businesses, "Synchronous and Asynchronous versions of this method should return the same thing."
      assert_same_elements [], businesses
    end

    test "includes businesses where user is billing manager but not org member with membership_type: :all and valid_license: false", skip_enterprise: true do
      businesses = @billing_manager.businesses membership_type: :all, valid_license: false
      async_businesses = @billing_manager.async_businesses(membership_type: :all, valid_license: false).sync

      assert_same_elements businesses, async_businesses, "Synchronous and Asynchronous versions of this method should return the same thing."
      assert_same_elements [@business_1, @business_3], businesses
    end

    test "includes businesses where user is billing manager and org member with membership_type: :all and valid_license: true", skip_enterprise: true do
      enable_feature_flag(:bus_ids_exclude_billing_manager_valid_license)
      @org.add_member @billing_manager
      businesses = @billing_manager.businesses membership_type: :all, valid_license: true
      async_businesses = @billing_manager.async_businesses(membership_type: :all, valid_license: true).sync

      assert_same_elements businesses, async_businesses, "Synchronous and Asynchronous versions of this method should return the same thing."
      assert_same_elements [@business_4], businesses
    end

    test "includes businesses where user is on unaffiliated member with membership_type: :all and include_unaffiliated when business is basic", skip_enterprise: true do
      user = create :user
      @business_1.update(seats_plan_type: :basic)
      @business_1.add_user_accounts([user.id], business_roles_bitfield: 0)

      businesses = user.businesses(include_unaffiliated: true)
      async_businesses = user.async_businesses(include_unaffiliated: true)

      assert_same_elements [@business_1], businesses
      assert_same_elements [@business_1], async_businesses.sync

      assert_equal [], user.businesses
      assert_equal [], user.async_businesses.sync
    end

    test "includes businesses where user is on unaffiliated member with membership_type: :all and include_unaffiliated when feature is enabled", skip_enterprise: true do
      enable_feature_flag(:unaffiliated_user_accounts)
      user = create :user
      @business_1.add_user_accounts([user.id], business_roles_bitfield: 0)

      businesses = user.businesses(include_unaffiliated: true)
      async_businesses = user.async_businesses(include_unaffiliated: true)

      assert_same_elements [@business_1], businesses
      assert_same_elements [@business_1], async_businesses.sync

      assert_equal [], user.businesses
      assert_equal [], user.async_businesses.sync
    end

    test "does not include businesses where user is flagged as a contractor", enterprise_only: true do
      EnterpriseAttestation.stubs(contractor?: true)
      businesses = @org_member.businesses
      async_businesses = @org_member.async_businesses

      assert_equal [], businesses
      assert_equal [], async_businesses.sync
    end

    test "raises an ArgumentError when membership_type is invalid" do
      assert_raises ArgumentError do
        @business_admin.businesses membership_type: :eeeeeeeeeeeeee
      end

      assert_raises ArgumentError do
        @business_admin.async_businesses(membership_type: :eeeeeeeeeeeeee).sync
      end
    end

    test "handles pagination" do
      businesses = @business_admin.businesses.paginate(page: 1, per_page: 1).order(:id)
      assert_same_elements [@business_1], businesses
      assert_equal 3, businesses.total_pages
      assert_equal 1, businesses.current_page
    end

    test "handles page count when last page is incomplete" do
      businesses = @business_admin.businesses.paginate(page: 1, per_page: 2).order(:id)
      assert_same_elements [@business_1, @business_2], businesses
      assert_equal 2, businesses.total_pages
      assert_equal 1, businesses.current_page
    end

    test "handles the first page when less than a page is present" do
      businesses = @business_admin.businesses.paginate page: 1, per_page: 10
      assert_same_elements [@business_1, @business_2, @business_3], businesses
      assert_equal 1, businesses.total_pages
      assert_equal 1, businesses.current_page
    end

    test "returns emu enterprise for emu user, even if they don't belong to any organizations", skip_enterprise: true do
      assert_includes @emu_user.businesses, @emu_business
    end
  end

  context "business_ids" do
    test "returns single value when member of a single business directly and via org" do
      @business_4.billing.add_manager @org_member, actor: @business_4.owners.first
      assert_equal [@business_4.id], @org_member.reload.business_ids
    end

    test "returns no ids when member is flagged as contractor", enterprise_only: true do
      EnterpriseAttestation.stubs(contractor?: true)
      assert_equal [], @org_member.business_ids
    end

    context "with internal repo visibility fix for EMUs with VSS", skip_enterprise: true do
      test "returns no ids when querying for licensed emus" do
        disable_feature_flag(:emu_vss_business, @emu_business)
        assert_equal [], @emu_user.business_ids(valid_license: true)
      end

      test "returns no ids when querying for licensed emus with VSS bundle" do
        disable_feature_flag(:emu_vss_business, @emu_business)
        create :enterprise_agreement, business: @emu_business
        assert_equal [], @emu_user.business_ids(valid_license: true)
      end

      context "with emu_vss_business feature enabled" do
        test "returns business id" do
          enable_feature_flag(:emu_vss_business, @emu_business)
          assert_equal [@emu_business.id], @emu_user.business_ids(valid_license: true)
        end

        test "increments metric" do
          enable_feature_flag(:emu_vss_business, @emu_business)
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
          @emu_user.business_ids(valid_license: true)
          assert_equal 1, GitHub.dogstats.increments("internal_repo_visibility_fix.enabled", tags: ["enterprise:#{@emu_business.slug}", "user:#{@emu_user.login}"]).count
        end
      end
    end

    context "emu guest collaborators", skip_enterprise: true do
      test "should only have access to internal repositories in organizations they belong to, given the organization base permissions are set to :read or greater" do
        # Default base permission is read
        assert_equal :read, @emu_org.default_repository_permission
        assert_same_elements [@emu_org_internal_repo], @guest_collaborator.internal_repositories

        @emu_org.update_default_repository_permission(:write, actor: @emu_owner)
        assert_equal :write, @emu_org.default_repository_permission
        assert_same_elements [@emu_org_internal_repo], @guest_collaborator.internal_repositories

        @emu_org.update_default_repository_permission(:admin, actor: @emu_owner)
        assert_equal :admin, @emu_org.default_repository_permission
        assert_same_elements [@emu_org_internal_repo], @guest_collaborator.internal_repositories
      end

      test "should not have access to internal repositories in organizations they belong to, given the organization base permissions are set to :none (No permission)" do
        @emu_org.update_default_repository_permission(:none, actor: @emu_owner)
        assert_equal :none, @emu_org.default_repository_permission
        assert_empty @guest_collaborator.internal_repositories
      end
    end
  end

  context "#is_business_member?" do
    test "is true for admin" do
      assert @business_admin.is_business_member?(@business_1.id)
    end

    test "is true for billing manager" do
      assert @billing_manager.is_business_member?(@business_1.id)
    end

    test "is true for biz org member" do
      assert @org_member.is_business_member?(@business_4.id)
    end

    test "is false for biz org member flagged as contractor", enterprise_only: true do
      EnterpriseAttestation.stubs(contractor?: true)
      refute @org_member.is_business_member?(@business_4.id)
    end

    test "is true for biz org admin" do
      assert @org_admin.is_business_member?(@business_4.id)
    end

    test "is false for admin of different business" do
      refute @business_admin.is_business_member?(@business_4.id)
    end

    test "is false for billing manager of different business" do
      refute @billing_manager.is_business_member?(@business_4.id)
    end

    test "is false for biz org member of different business" do
      refute @org_member.is_business_member?(@business_1.id)
    end

    test "is false for biz org admin of different business" do
      refute @org_admin.is_business_member?(@business_1.id)
    end
  end

  context "#internal_repositories" do
    test "returns repositories for member" do
      internal_repo = create(:internal_repository, owner: @org)

      assert_equal [internal_repo], @org_member.internal_repositories
    end

    test "returns no repositories for member flagged as contractor", enterprise_only: true do
      internal_repo = create(:internal_repository, owner: @org)

      EnterpriseAttestation.stubs(contractor?: true)
      assert_equal [], @org_member.internal_repositories
    end

    test "returns no repositories for a member with direct collaborator permissions when flagged as contractor", enterprise_only: true do
      internal_repo = create(:internal_repository, owner: @org)
      internal_repo.add_member(@org_member, action: :write)

      EnterpriseAttestation.stubs(contractor?: true)
      assert_equal [], @org_member.internal_repositories
    end

    test "returns no repositories for a member flagged as contractor indirect access through a team" do
      internal_repo = create(:internal_repository, owner: @org)
      team = create(:team, organization: @org)
      team.add_repository(internal_repo, :push)
      team.add_member(@org_member)

      EnterpriseAttestation.stubs(contractor?: true)
      assert_equal [], @org_member.internal_repositories
    end

    test "returns no repositories for billing manager that isn't a member of an org" do
      enable_feature_flag(:bus_ids_exclude_billing_manager_valid_license)
      assert_empty @billing_manager.internal_repositories
    end

    test "returns repositories for billing manager that is a member of an org" do
      @org.add_member @billing_manager
      internal_repo = create(:internal_repository, owner: @org)
      assert_equal [internal_repo], @billing_manager.internal_repositories
    end
  end

  context "#verify_no_owned_businesses" do
    if GitHub.enterprise?
      test "does not prevent removal of user if is owner of a business" do
        assert @business_admin.destroy
        refute @business_admin.errors[:enterprises].any?
      end
    else
      test "prevents removal of user if is owner of a business", skip_with_all_emus: true do
        refute @business_admin.destroy
        assert @business_admin.errors[:enterprises].any?
      end

      test "does not prevent removal of EMU users", skip_enterprise: true do
        assert @emu_owner.destroy
        refute @business_admin.errors[:enterprises].any?
      end
    end
  end

  context "#direct_and_indirect_orgs" do
    test "with param, returns orgs that user is directly and indirectly related to" do
      disable_feature_flag(:cap_filter_consider_outside_collabs)
      business_org = create(:organization, business: @business_1)
      collab_org = create(:organization)
      repo = create(:repository, owner: collab_org)
      RepositoryInvitation.invite_to_repo_without_confirmation(@org_member, collab_org.owner, repo)

      assert @org_member.direct_and_indirect_orgs.include?(@org)
      assert @business_admin.direct_and_indirect_orgs.include?(business_org)
      refute @org_member.direct_and_indirect_orgs.include?(collab_org)
    end

    test "with cap_filter_consider_outside_collabs FF, also returns orgs that own repos user is an outside collaborator of" do
      enable_feature_flag(:cap_filter_consider_outside_collabs)
      business_org = create(:organization, business: @business_1)
      collab_org = create(:organization)
      repo = create(:repository, owner: collab_org)
      RepositoryInvitation.invite_to_repo_without_confirmation(@org_member, collab_org.owner, repo)

      assert @org_member.direct_and_indirect_orgs.include?(@org)
      assert @business_admin.direct_and_indirect_orgs.include?(business_org)
      assert @org_member.direct_and_indirect_orgs.include?(collab_org)
    end
  end
end
