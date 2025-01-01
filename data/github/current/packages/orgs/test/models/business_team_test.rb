# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessTeamTest < GitHub::TestCase
  fixtures do
    @admin = create :user
    @business = create(:business, owners: [@admin])
    @org0 = create(:business_plus_organization, business: @business)
    @org1 = create(:organization, business: @business)
    @org2 = create(:organization, business: @business)
    @business_team = BusinessTeam.create!(name: "business-team", business: @business, organization_selection_type: :selected, privacy: :closed)
    @business_team_org0_assignment = BusinessTeamOrgAssignment.create!(business_team: @business_team, organization: @org0)
    @business_team_org1_assignment = BusinessTeamOrgAssignment.create!(business_team: @business_team, organization: @org1)
    @global_business_team = BusinessTeam.create!(name: "global-business-team", business: @business, organization_selection_type: :all)

    @user0 = create(:user)
    create(:business_user_account, user: @user0, business: @business, business_roles_bitfield: 0)
    @user1 = create(:user)
    create(:business_user_account, user: @user1, business: @business, business_roles_bitfield: 0)
    @member = create(:user)
    @org0.add_member(@member)

    enable_feature_flag(:enterprise_teams_crud, @business)
    enable_feature_flag(:enterprise_teams_org_assignment, @business)
    disable_feature_flag(:enterprise_teams_enabled_for_organizations, @business)

    perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob
  end

  context "default_scope" do
    test "is undoing orgid is not null" do
      expected_team = BusinessTeam.create!(name: "some-team", slug: "some-team", business: @business)
      actual_team = BusinessTeam.find_by(business: @business, slug: "some-team")
      refute_nil actual_team
      assert_equal expected_team, actual_team
      assert_nil T.must(actual_team).organization_id
    end
  end

  context "validations" do
    test "validates presence of business" do
      assert_raises(ActiveRecord::RecordInvalid) do
        BusinessTeam.create!(name: "some-team", business: nil)
      end

      assert_predicate BusinessTeam.create(name: "some-team", business: @business), :valid?
    end

    test "validates correct organization_selection_type" do
      assert_raises ArgumentError do
        @business_team.organization_selection_type = :foo
      end
    end

    test "validates uniqueness of name scoped to business_id" do
      business_team = BusinessTeam.create!(name: "Unique Team", business: @business)
      duplicate_team = BusinessTeam.new(name: "UNIQUE TEAM", business: @business)

      refute duplicate_team.valid?
      assert_match(/has already been taken/, duplicate_team.errors[:name].first)
    end

    test "validates absence of organization_id" do
      assert_raises(ActiveRecord::RecordInvalid) do
        BusinessTeam.create!(name: "some-team", business: @business, organization_id: @org0.id)
      end

      assert_raises(ActiveRecord::RecordInvalid) do
        @business_team.update!(organization_id: @org0.id)
      end
    end

    test "validates business has not reached team limit on creation" do
      no_limit_team = BusinessTeam.create(name: "no limit team", business: @business)
      assert_predicate no_limit_team, :valid?

      BusinessTeam.any_instance.stubs(:business_teams_limit_reached?).returns(true)
      limit_team = BusinessTeam.create(name: "limit team", business: @business)
      refute_predicate limit_team, :valid?
      refute_nil limit_team.errors.of_kind?(:business, "team creation limit reached")
    end
  end

  context "relations" do
    test "#belongs_to :business" do
      assert_equal @business, @business_team.business
    end

    test "#has_many :business_team_org_assignments" do
      assert_same_elements [@business_team_org0_assignment, @business_team_org1_assignment], @business_team.business_team_org_assignments
    end

    test "#has_many :selected_organizations" do
      assert_same_elements [@org0, @org1], @business_team.selected_organizations
      assert_empty @global_business_team.selected_organizations
    end
  end

  context "#destroy!" do
    test "destroys org assignments" do
      business_team = create(:business_team, business: @business)
      BusinessTeamOrgAssignment.create!(business_team: business_team, organization: @org0)
      BusinessTeamOrgAssignment.create!(business_team: business_team, organization: @org1)
      assert_equal 2, BusinessTeamOrgAssignment.where(team_id: business_team.id).count

      business_team.destroy!
      perform_enqueued_jobs only: DestroyTeamDependantsJob

      assert_empty BusinessTeamOrgAssignment.where(team_id: business_team.id)
    end

    test "unsubscribes all users" do
      business_team = create(:business_team, business: @business)
      business_team.add_member(@user0, caller_type: :business_team)
      business_team.add_member(@user1, caller_type: :business_team)
      assert_predicate GitHub.newsies.subscription_status(@user0, business_team), :subscribed?
      assert_predicate GitHub.newsies.subscription_status(@user1, business_team), :subscribed?

      perform_enqueued_jobs(only: [DestroyTeamDependantsJob, Newsies::DeleteAllForListJob]) do
        business_team.destroy!
        refute_predicate GitHub.newsies.subscription_status(@user0, business_team), :subscribed?
        refute_predicate GitHub.newsies.subscription_status(@user1, business_team), :subscribed?
      end
    end

    test "destroys any associated UserRole records" do
      business_team = create(:business_team, business: @business)
      repo = create(:repository, :minimal, owner: @org0)
      create :user_role, actor: business_team, role: Role.triage_role, target: repo

      assert_equal 1, business_team.user_roles.count

      assert_difference("UserRole.count", -1) do
        perform_enqueued_jobs(only: [DestroyTeamDependantsJob]) do
          business_team.destroy!
        end
      end

      assert_empty UserRole.where(actor: business_team)
    end

    test "destroys any associated Ability records" do
      business_team = create(:business_team, business: @business)
      business_team.bulk_add_members([@user0, @user1], caller_type: :business_team)

      assert_equal 2, Ability.where(subject: business_team).count

      perform_enqueued_jobs(only: [DestroyTeamDependantsJob]) do
        business_team.destroy!
      end

      assert_empty Ability.where(subject: business_team)
    end
  end

  test "business_team?" do
    assert @business_team.business_team?
  end

  context "#locally_managed?" do
    test "returns false for a business team" do
      refute @business_team.locally_managed?
    end

    test "returns false for another business team instance" do
      another_business_team = create(:business_team, business: @business)
      refute another_business_team.locally_managed?
    end
  end

  context "enabled_for_enterprise?" do
    test "returns false if business is nil" do
      refute BusinessTeam.enabled_for_enterprise?(business: nil)
    end

    test "returns false if enterprise_teams_enabled_for_organizations is enabled" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      refute BusinessTeam.enabled_for_enterprise?(business: @business)
    end

    test "returns false if business_teams_enabled_for_enterprise is not enabled" do
      disable_feature_flag(:enterprise_teams_crud)
      disable_feature_flag(:erp_staffship_enterprise_teams_crud)
      disable_feature_flag(:erp_preview_enterprise_teams_crud)
      refute BusinessTeam.enabled_for_enterprise?(business: @business)
    end

    test "returns true if business_teams_enabled_for_enterprise is enabled" do
      assert BusinessTeam.enabled_for_enterprise?(business: @business)
    end
  end

  context "organization_ids" do
    test "returns all organization ids if organization_selection_type is all_orgs" do
      assert_same_elements @business.organization_ids, @global_business_team.organization_ids
    end

    test "returns all organization ids if organization_selection_type is all_orgs except soft deleted ones", skip_enterprise: true do
      org3 = create(:organization, business: @business)
      org3.soft_delete!
      assert_same_elements @business.organization_ids, @global_business_team.organization_ids
    end

    test "returns selected organization ids if organization_selection_type is selected_orgs" do
      assert_same_elements [@org0.id, @org1.id], @business_team.organization_ids
    end

    test "returns selected organization ids excluding soft deleted ids", skip_enterprise: true do
      org3 = create(:organization, business: @business)
      business_team = create(:business_team, business: @business, name: "sel3", organization_selection_type: :selected)

      business_team.add_to_organizations(org_ids: [@org0.id, org3.id])
      business_team.reload
      assert_same_elements [@org0.id, org3.id], business_team.organization_ids

      org3.soft_delete!
      business_team.reload

      assert_same_elements [@org0.id], business_team.organization_ids
      assert_same_elements [@org0.id], business_team.selected_organization_ids
      assert_same_elements [@org0], business_team.organizations
      assert_same_elements [@org0], business_team.selected_organizations
      assert business_team.is_associated_with_organization?(@org0)
      refute business_team.is_associated_with_organization?(org3)

      assert_same_elements [@org0, org3], business_team.business_team_org_assignments.map(&:organization)
      assert_equal 2, business_team.business_team_org_assignment_ids.size
    end
  end

  context "is_associated_with_organization?" do
    test "returns false if business teams feature flag is disabled" do
      disable_feature_flag(:enterprise_teams_org_assignment)
      disable_feature_flag(:erp_staffship_enterprise_teams_org_assignment)
      disable_feature_flag(:erp_preview_enterprise_teams_org_assignment)
      refute @business_team.is_associated_with_organization?(@org0)
    end

    test "returns true if business team is associated with selected org and type is selected" do
      assert @business_team.is_associated_with_organization?(@org0)
    end

    test "returns true if business team is associated with business org and type is all" do
      assert @global_business_team.is_associated_with_organization?(@org0)
    end

    test "returns false if business team org selection type is disabled" do
      team_org_selection_disabled = BusinessTeam.create!(name: "team-org-selection-disabled", business: @business, organization_selection_type: :disabled)
      refute team_org_selection_disabled.is_associated_with_organization?(@org0)
    end
  end

  context "add_to_organizations" do
    test "does nothing if organization_selection_type is all_orgs" do
      @global_business_team.add_to_organizations(org_ids: [@org2.id])
      assert_empty @global_business_team.selected_organizations
    end

    test "adds the team to the selected organizations" do
      @business_team.add_to_organizations(org_ids: [@org2.id])
      assert_same_elements @business.organizations, @business_team.reload.selected_organizations
    end

    test "does not add more organization assignments than allowed by limit" do
      @business_team.stubs(:organization_assignments_allowed_to_add).returns(0)
      @business_team.add_to_organizations(org_ids: [@org2.id])
      refute_includes @business_team.reload.selected_organizations.pluck(:id), @org2.id
    end

    test "add org limit and org soft deletes", skip_enterprise: true do
      business_team = create(:business_team, business: @business, organization_selection_type: :selected)
      business_team.stubs(:limit_organization_assignments).returns(4)
      assert_equal 4, business_team.organization_assignments_allowed_to_add
      refute business_team.organization_assignment_limit_reached?

      org3 = create(:organization, business: @business)

      business_team.add_to_organizations(org_ids: [@org0.id, @org1.id, @org2.id, org3.id])
      assert_equal 0, business_team.organization_assignments_allowed_to_add
      assert business_team.organization_assignment_limit_reached?

      org3.soft_delete!
      assert_equal 1, business_team.organization_assignments_allowed_to_add
      refute business_team.organization_assignment_limit_reached?
    end
  end

  context "remove_from_organizations" do
    test "removes the team from the selected organization" do
      @business_team.remove_from_organizations(org_ids: [@org0.id])
      assert_equal [@org1], @business_team.selected_organizations
    end

    test "removes the team from the selected organizations" do
      @business_team.remove_from_organizations(org_ids: [@org0.id, @org1.id])
      assert_empty @business_team.selected_organizations
    end
  end

  context "slug generation" do
    test "generates a slug from the business team name" do
      business_team = BusinessTeam.create!(name: "Fun name", business: @business)
      assert_equal "fun-name", business_team.slug
    end

    test "generates a unique slug when same slug exists" do
      business_team1 = BusinessTeam.create!(name: "Fun name yay", business: @business)
      business_team2 = BusinessTeam.create!(name: "Fun-name yay", business: @business)
      business_team3 = BusinessTeam.create!(name: "Fun name-yay", business: @business)

      assert_equal "fun-name-yay", business_team1.slug
      assert_equal "fun-name-yay-1", business_team2.slug
      assert_equal "fun-name-yay-2", business_team3.slug
    end

    test "different businesses can have the same slug" do
      @business2 = create :business
      business_team = BusinessTeam.create!(name: "Same name", business: @business,)
      team_from_different_org = BusinessTeam.create!(name: "Same name", business: @business2)
      assert_equal "same-name", business_team.slug
      assert_equal "same-name", team_from_different_org.slug
    end unless GitHub.single_business_environment?

    test "does not do anything if the name has not changed" do
      business_team = BusinessTeam.create!(name: "Not changed", business: @business)
      business_team.reload
      business_team.expects(:generate_unique_slug).never
      business_team.save!
    end

    test "regenerates the slug when the name changes" do
      business_team = BusinessTeam.create!(name: "Not changed", business: @business)
      business_team.name = "Name has been changed"
      business_team.save!
      assert_equal "name-has-been-changed", business_team.slug
    end

    test "combined_slug" do
      assert_equal "/business-team", @business_team.combined_slug
    end
  end

  test "creator" do
    assert_equal @business, @business_team.creator
  end

  test "target_for_conditional_access" do
    assert_equal @business, @business_team.target_for_conditional_access
  end

  test "licensed_customer_id" do
    assert_equal @business.customer_id, @business_team.licensed_customer_id
    assert_equal @business.customer.id, @business_team.licensed_customer_id
  end

  context "bulk_add_members" do
    test "#successful for multiple users" do
      status = @business_team.bulk_add_members([@user0, @user1], caller_type: :business_team)
      assert_same_elements([@user0, @user1], @business_team.members)
      assert Ability.find_by(actor_id: @user0.id, actor_type: "User", subject_id: @business_team.id, subject_type: "BusinessTeam")
      assert Ability.find_by(actor_id: @user1.id, actor_type: "User", subject_id: @business_team.id, subject_type: "BusinessTeam")
      assert_equal Team::AddMemberStatus::SUCCESS, status
    end

    test "#filters out non-business users" do
      user = create(:user)
      @business_team.bulk_add_members([@user0, @user1, user], caller_type: :business_team)
      assert_same_elements([@user0, @user1], @business_team.members)
      refute Ability.find_by(actor_id: user.id, actor_type: "User", subject_id: @business_team.id, subject_type: "BusinessTeam")
    end unless GitHub.single_business_environment?

    test "#ignores caller overriding skip options to not skip org specific steps" do
      @business.expects(:update_license_usage).never
      @business_team.expects(:bulk_validate_add_members_to_orgs).never

      status = @business_team.bulk_add_members([@user0, @user1], {
        skip_create_organization_memberships: false,
        skip_license_usage_update: false,
        caller_type: :business_team
      })
      assert_same_elements([@user0, @user1], @business_team.members)
      assert Ability.find_by(actor_id: @user0.id, actor_type: "User", subject_id: @business_team.id, subject_type: "BusinessTeam")
      assert Ability.find_by(actor_id: @user1.id, actor_type: "User", subject_id: @business_team.id, subject_type: "BusinessTeam")
      assert_equal Team::AddMemberStatus::SUCCESS, status
    end

    test "#return NOT_USER" do
      status  = @business_team.bulk_add_members([])
      assert_equal Team::AddMemberStatus::NOT_USER, status
    end

    test "#does nothing when feature is not enabled" do
      disable_feature_flag(:enterprise_teams_crud)
      disable_feature_flag(:erp_staffship_enterprise_teams_crud)
      disable_feature_flag(:erp_preview_enterprise_teams_crud)
      assert_equal Team::AddMemberStatus::NO_PERMISSION, @business_team.bulk_add_members([@user0])
    end

    test "does not add more members than allowed by limit" do
      @business_team.stubs(:members_allowed_to_add).returns(1)
      status = @business_team.bulk_add_members([@user0, @user1], caller_type: :business_team)
      assert_equal 1, @business_team.members.count
    end

    test "bulk_add_members returns NOT_USER when given an empty users array" do
      assert_equal Team::AddMemberStatus::NOT_USER, @business_team.bulk_add_members([], caller_type: :business_team)
    end

    test "auto subscribe to org repos doesn't do anything if not associated to org" do
      repo1 = create :private_repository, owner: @org0, from_example: :simple
      repo2 = create :private_repository, owner: @org0, from_example: :simple

      users = Array.new(4).map do
        user = create :user
        GitHub.newsies.get_and_update_settings(user) do |settings|
          settings.auto_subscribe_repositories = true
        end
        create(:business_user_account, user: user, business: @business, business_roles_bitfield: 0)
        user
      end

      team = create :business_team, business: @business, organization_selection_type: :disabled
      team.add_repository repo1, "push"
      assert_difference("GitHub.newsies.count_subscribers(repo1).count", 0) do
        assert_no_enqueued_jobs(only: [Newsies::AutoSubscribeUserToRepositoriesJob]) do
          team.bulk_add_members(users, caller_type: :business_team)
        end
      end

      assert_difference("GitHub.newsies.count_subscribers(repo2).count", 0) do
        assert_no_enqueued_jobs(only: [Newsies::AutoSubscribeUsersToRepositoryJob]) do
          team.add_repository repo2, :push
        end
      end
    end

    test "if associated to org, auto subscribe to org repos skipped during add_members, works for repos added later" do
      repo1 = create :private_repository, owner: @org0, from_example: :simple
      repo2 = create :private_repository, owner: @org0, from_example: :simple

      users = Array.new(4).map do
        user = create :user
        GitHub.newsies.get_and_update_settings(user) do |settings|
          settings.auto_subscribe_repositories = true
        end
        create(:business_user_account, user: user, business: @business, business_roles_bitfield: 0)
        user
      end

      team = create :business_team, business: @business, organization_selection_type: :all
      team.add_repository repo1, "push"
      assert_difference("GitHub.newsies.count_subscribers(repo1).count", 0) do
        assert_no_enqueued_jobs(only: [Newsies::AutoSubscribeUserToRepositoriesJob]) do
          team.bulk_add_members(users, caller_type: :business_team)
        end
      end

      assert_difference("GitHub.newsies.count_subscribers(repo2).count", 4) do
        perform_enqueued_jobs(only: [Newsies::AutoSubscribeUsersToRepositoryJob]) do
          team.add_repository repo2, :push
        end
      end
    end
  end

  context "bulk_add_members_with_failover" do
    test "#succeeds" do
      status = @business_team.bulk_add_members_with_failover([@user0, @user1], caller_type: :business_team)
      assert_same_elements([@user0, @user1], @business_team.members)
      assert Ability.find_by(actor_id: @user0.id, actor_type: "User", subject_id: @business_team.id, subject_type: "BusinessTeam")
      assert Ability.find_by(actor_id: @user1.id, actor_type: "User", subject_id: @business_team.id, subject_type: "BusinessTeam")
      assert_equal [Team::AddMemberStatus::SUCCESS], status
    end

    test "#calls bulk_add_members" do
      # Create a mock for the bulk_add_members method to confirm call
      mock = Minitest::Mock.new
      mock.expect(:call, Team::AddMemberStatus::SUCCESS, [[@user0, @user1], Hash])

      # Replace the bulk_add_members method with the mock
      @business_team.define_singleton_method(:bulk_add_members) do |*args|
        mock.call(*args)
      end

      # Call the method under test
      result = @business_team.bulk_add_members_with_failover([@user0, @user1])

      # Assertions
      assert_equal [Team::AddMemberStatus::SUCCESS], result

      # Verify the expectations
      mock.verify
    end
  end

  context "add_member" do
    test "#succeeds" do
      status = @business_team.add_member(@user0, caller_type: :business_team)
      assert_same_elements([@user0], @business_team.members)
      assert Ability.find_by(actor_id: @user0.id, actor_type: "User", subject_id: @business_team.id, subject_type: "BusinessTeam")
      assert_equal Team::AddMemberStatus::SUCCESS, status
    end

    test "#calls bulk_add_members" do
      # Create a mock for the bulk_add_members method to confirm call
      mock = Minitest::Mock.new
      mock.expect(:call, Team::AddMemberStatus::SUCCESS, [[@user0], Hash])

      # Replace the bulk_add_members method with the mock
      @business_team.define_singleton_method(:bulk_add_members) do |*args|
        mock.call(*args)
      end

      # Call the method under test
      result = @business_team.add_member(@user0)

      # Assertions
      assert_equal Team::AddMemberStatus::SUCCESS, result

      # Verify the expectations
      mock.verify
    end

    test "add_member does not add member when caller_type is not :business_team" do
      refute_includes @business_team.members, @user0

      @business_team.add_member(@user0, caller_type: :unacceptable_caller_type)

      refute_includes @business_team.members, @user0
    end
  end

  context "remove members" do
    test "#successful for multiple users" do
      @business_team.bulk_add_members([@user0, @user1])

      perform_enqueued_jobs(only: DenyForkCollabStateForUserPullRequestsJob) do
        @business_team.bulk_remove_members(users: [@user0, @user1], caller_type: :business_team)
      end

      assert_empty @business_team.members
      refute Ability.find_by(actor_id: @user0.id, actor_type: "User", subject_id: @business_team.id, subject_type: "BusinessTeam")
      refute Ability.find_by(actor_id: @user1.id, actor_type: "User", subject_id: @business_team.id, subject_type: "BusinessTeam")
    end

    test "#remove single member works" do
      @business_team.add_member(@user0)

      perform_enqueued_jobs(only: DenyForkCollabStateForUserPullRequestsJob) do
        @business_team.remove_member(@user0)
      end

      assert_empty @business_team.members
      refute Ability.find_by(actor_id: @user0.id, actor_type: "User", subject_id: @business_team.id, subject_type: "BusinessTeam")
    end

    test "#subscriptions are cleaned up when removing users" do
      assert GitHub.newsies.settings(@user0).auto_subscribe_teams?
      assert GitHub.newsies.settings(@user1).auto_subscribe_teams?
      @business_team.bulk_add_members([@user0, @user1], caller_type: :business_team)
      assert_predicate GitHub.newsies.subscription_status(@user0, @business_team), :subscribed?
      assert_predicate GitHub.newsies.subscription_status(@user1, @business_team), :subscribed?

      perform_enqueued_jobs(only: Newsies::DeleteAllForUserAndListsJob) do
        @business_team.bulk_remove_members(users: [@user0, @user1], caller_type: :business_team)
      end

      refute_predicate GitHub.newsies.subscription_status(@user0, @business_team), :subscribed?
      refute_predicate GitHub.newsies.subscription_status(@user1, @business_team), :subscribed?
    end

    test "bulk_remove_members does not remove members when caller_type is not :business_team" do
      @business_team.bulk_add_members([@user0], caller_type: :business_team)
      assert_includes @business_team.members, @user0

      @business_team.bulk_remove_members(users: [@user0], caller_type: :unacceptable_caller_type)
      assert_includes @business_team.members, @user0
    end
  end

  context "#direct_or_inherited_repo_ids" do
    test "returns immediate repo ids when affiliation is :immediate" do
      immediate_repo = create :private_repository, :minimal, owner: @org0
      inherited_repo = create :private_repository, :minimal, owner: @org0

      child_team = BusinessTeam.create!(name: "child-team", business: @business, organization_selection_type: :selected, parent_team_id: @business_team.id)
      BusinessTeamOrgAssignment.create!(business_team: child_team, organization: @org0)

      @business_team.add_repository(inherited_repo, :pull)
      child_team.add_repository(immediate_repo, :pull)

      assert_same_elements [immediate_repo.id], child_team.direct_or_inherited_repo_ids(affiliation: :immediate)
    end

    # BusinessTeam inheritance is not implemented yet
    # so this just returns direct repo ids
    test "returns immediate repo ids when affiliation is :all" do
      immediate_repo = create :private_repository, :minimal, owner: @org0
      inherited_repo = create :private_repository, :minimal, owner: @org0

      child_team = BusinessTeam.create!(name: "child-team", business: @business, organization_selection_type: :selected, parent_team_id: @business_team.id)
      BusinessTeamOrgAssignment.create!(business_team: child_team, organization: @org0)

      @business_team.add_repository(inherited_repo, :pull)
      child_team.add_repository(immediate_repo, :pull)

      assert_same_elements [immediate_repo.id], child_team.direct_or_inherited_repo_ids(affiliation: :all)
    end

    # BusinessTeam inheritance is not implemented yet
    # so this returns an empty array
    test "returns no repo ids when affilation is :inherited" do
      immediate_repo = create :private_repository, :minimal, owner: @org0
      inherited_repo = create :private_repository, :minimal, owner: @org0

      child_team = BusinessTeam.create!(name: "child-team", business: @business, organization_selection_type: :selected, parent_team_id: @business_team.id)
      BusinessTeamOrgAssignment.create!(business_team: child_team, organization: @org0)

      @business_team.add_repository(inherited_repo, :pull)
      child_team.add_repository(immediate_repo, :pull)

      assert_raises("Not Implemented") do
        assert_empty child_team.direct_or_inherited_repo_ids(affiliation: :inherited)
      end
    end
  end

  context "remove_repository" do
    test "remove_repository removes a repository from a business team" do
      business_team = create(:business_team, business: @business, organization_selection_type: :all)
      private_repo = create(:private_repository, :minimal, owner: @org0)
      business_team.add_repository(private_repo, :admin)
      private_repo.reload
      assert_able business_team, :admin, private_repo

      business_team.remove_repository(private_repo)
      private_repo.reload
      refute_able business_team, :admin, private_repo
    end
  end

  context "update_repository_permission" do
    test "update_repository_permission update a symbol repository permission for a business team" do
      business_team = create(:business_team, business: @business, organization_selection_type: :all)
      private_repo = create(:private_repository, :minimal, owner: @org0)
      business_team.add_repository(private_repo, :read)
      private_repo.reload
      assert_able business_team, :read, private_repo
      refute_able business_team, :admin, private_repo

      business_team.update_repository_permission(private_repo, :admin)
      private_repo.reload
      assert_able business_team, :admin, private_repo
    end

    test "update_repository_permission update a string repository permission for a business team" do
      business_team = create(:business_team, business: @business, organization_selection_type: :all)
      private_repo = create(:private_repository, :minimal, owner: @org0)
      business_team.add_repository(private_repo, :read)
      private_repo.reload
      assert_able business_team, :read, private_repo
      refute_able business_team, :admin, private_repo

      business_team.update_repository_permission(private_repo, "admin")
      private_repo.reload
      assert_able business_team, :admin, private_repo
    end

    test "update_repository_permission handles invalid permissions" do
      business_team = create(:business_team, business: @business, organization_selection_type: :all)
      private_repo = create(:private_repository, :minimal, owner: @org0)
      business_team.add_repository(private_repo, :read)
      private_repo.reload
      response = business_team.update_repository_permission(private_repo, "invalid")
      assert_equal(response, Team::ModifyRepositoryStatus::NO_PERMISSION)
    end

    test "update_repository_permission handles invalid business" do
      business_team = create(:business_team, business: @business, organization_selection_type: :all)
      org = create(:organization)
      private_repo = create(:private_repository, :minimal, owner: org)
      business_team.update_repository_permission(private_repo, "admin")
      response = business_team.update_repository_permission(private_repo, "invalid")
      assert_equal(response, Team::ModifyRepositoryStatus::NOT_OWNED)
    end
  end

  context "visible_to?" do
    test "returns false if viewer is nil" do
      refute @business_team.visible_to?(nil)
    end

    test "returns true if viewer is member of the business team" do
      refute @business_team.visible_to?(@user0)
      @business_team.add_member(@user0, caller_type: :business_team)
      assert @business_team.visible_to?(@user0)
    end

    test "returns true if viewer is admin of the business" do
      assert @business_team.visible_to?(@admin)
    end

    test "returns true if viewer is admin of one of the orgs the business team is visible in" do
      admin = create(:user)
      refute @business_team.visible_to?(admin)
      @org0.add_admin(admin)
      assert @business_team.visible_to?(admin)
    end

    test "returns true if viewer is member of one of the orgs the business team is visible in and the team is not secret" do
      assert @business_team.visible_to?(@member)
    end

    test "returns false when the member is not a member of the org" do
      refute @business_team.visible_to?(@user0)
    end
  end

  context "tenant_slug_for_avatar" do
    test "tenant_slug_for_avatar returns correct slug" do
      if GitHub.multi_tenant_enterprise?
        assert_equal @business&.slug, @business_team.tenant_slug_for_avatar
      else
        assert_equal "", @business_team.tenant_slug_for_avatar
      end
    end
  end

  context "#eligible_members_in_enterprise" do
    test "includes business member" do
      members = @business_team.eligible_members_in_enterprise(@admin)
      assert_includes members.pluck(:login), @member.login
    end

    test "includes unaffiliated business member" do
      enable_feature_flag(:unaffiliated_user_accounts)
      members = @business_team.eligible_members_in_enterprise(@admin)
      assert_includes members.pluck(:login), @user0.login
    end

    test "does not include existing member of business team" do
      @business_team.add_member(@member, caller_type: :business_team)
      members = @business_team.eligible_members_in_enterprise(@admin)
      refute_includes members.pluck(:login), @member.login
    end

    test "does not show any results for non-admin users" do
      assert_empty @business_team.eligible_members_in_enterprise(@member)
      assert_empty @business_team.eligible_members_in_enterprise(@user0)
    end
  end
end
