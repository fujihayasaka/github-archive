# typed: true
# frozen_string_literal: true

require "test_helper"
class EnterpriseTeamTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  fixtures do
    if GitHub.single_business_environment?
      setup_saml_auth_mode(with_scim: true)
      @business = create :global_business
      @provider = create :business_saml_provider, business: @business
      @provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")
      @owner = @business.owners.first
    else
      @owner = create :emu, :owner
      @business = @owner.enterprise_managed_business
    end

    @external_identity = @owner.external_identities.first
    @organization = create :organization, business: @business

    # GHAS enabled organization
    @ghas_organization = create :organization, business: @business
    @ghas_repo = create :private_repository, owner: @ghas_organization
    @ghas_repo_config = create(:repository_security_center_config, repository: @ghas_repo, ghas_enabled: true)

    @team = create :enterprise_team, business: @business
    @external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)
    @enterprise_team_group_mapping = EnterpriseTeamGroupMapping.create!(enterprise_team: @team, external_group: @external_group)
  end

  setup do
    if GitHub.single_business_environment?
      GitHub.stubs(:esm_enabled?).returns(true)
      setup_saml_auth_mode(with_scim: true)
    end
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
  end

  context ".max_sync_organizations" do
    test "returns the default value if config override is not set" do
      GitHub.stubs(:esm_max_sync_organizations_override).returns(nil)
      assert_equal EnterpriseTeam::DEFAULT_MAX_SYNC_ORGANIZATIONS, EnterpriseTeam.max_sync_organizations
    end

    test "returns the config override if set" do
      expected = 42
      GitHub.stubs(:esm_max_sync_organizations_override).returns(expected)
      assert_equal expected, EnterpriseTeam.max_sync_organizations
    end
  end

  context "validations" do
    test "is valid with a name and slug" do
      assert_predicate @team, :persisted?
    end

    context "sync to organizations" do
      test "fails with an invalid setting" do
        assert_raises ActiveRecord::RecordInvalid do
          create :enterprise_team, sync_to_organizations: "asjdhjlksahjdklw", business: @business
        end
      end

      test "fails with a null setting" do
        assert_raises(TypeError) do
          @team.sync_to_organizations = nil
          @team.save!
        end
      end

      test "default value" do
        assert_equal "disabled", (create :enterprise_team, business: @business).sync_to_organizations
      end

      test "is OK with value disabled" do
        assert create :enterprise_team, sync_to_organizations: :disabled, business: @business
      end

      test "is OK with value all" do
        assert create :enterprise_team, sync_to_organizations: :all, business: @business
      end
    end
  end

  context "create" do
    test "enterprise_team.create is emitted for a new enterprise team" do
      events = subscribe("enterprise_team.create")
      enterprise_team = create :enterprise_team, business: @business

      expected_payload = {
        business_id: enterprise_team.business.id,
        business: enterprise_team.business.slug,
        enterprise_team_id: enterprise_team.id,
        enterprise_team: enterprise_team.slug,
      }

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.create", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "destroy" do
    test "dependants are deleted via destroy_dependents_in_background when the enterprise_team is destroyed" do
      @team.enterprise_team_assignments.create!(enterprise_team: @team, assignment_type: :copilot)
      @team.enterprise_team_memberships.create!(user_id: create(:user).id)
      EnterpriseTeamOrganizationMapping.create!(enterprise_team: @team, organization: @organization)

      assert_difference({
        "EnterpriseTeam.count" => -1,
        "EnterpriseTeamGroupMapping.count" => -1,
        "EnterpriseTeamAssignment.count" => -1,
        "EnterpriseTeamMembership.count" => -1,
        "EnterpriseTeamOrganizationMapping.count" => -1,
      }) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          @team.destroy!
        end
      end
    end

    test "destroying an ET removes users from orgs that were only in the org because of membership to an ET managed team" do
      synced_enterprise_team = create :enterprise_team, business: @business, sync_to_organizations: "all"
      synced_enterprise_team.bulk_add_members(users: [@owner])
      org_team = create :team, organization: @organization
      EnterpriseTeamOrganizationMapping.create(enterprise_team: synced_enterprise_team, organization: @organization, team: org_team)
      perform_enqueued_jobs(only: [EnterpriseTeamOrganizationReconciliationRunnerJob]) do
        EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: synced_enterprise_team.id)
      end
      assert @organization.member_ids.include?(@owner.id)

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob, DestroyTeamDependantsJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        synced_enterprise_team.destroy
      end

      refute @organization.member_ids.include?(@owner.id)
    end

    test "destroying an ET removes users from orgs that were only in the org because of membership to an ET managed team: no email" do
      Team::Destruction::DestroyDependantsOperation.any_instance.expects(:send_removal_notification).never
      OrganizationMailer.expects(:removed_from_org).never
      synced_enterprise_team = create :enterprise_team, business: @business, sync_to_organizations: "all"
      synced_enterprise_team.bulk_add_members(users: [@owner])
      org_team = create :team, organization: @organization
      EnterpriseTeamOrganizationMapping.create(enterprise_team: synced_enterprise_team, organization: @organization, team: org_team)
      perform_enqueued_jobs(only: [EnterpriseTeamOrganizationReconciliationRunnerJob]) do
        EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: synced_enterprise_team.id)
      end
      assert @organization.member_ids.include?(@owner.id)

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob, DestroyTeamDependantsJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        synced_enterprise_team.destroy
      end

      refute @organization.member_ids.include?(@owner.id)
    end

    test "unassignment events are emitted when team is deleted" do
      enterprise_team = create :enterprise_team, business: @business
      new_events = subscribe("enterprise_team.copilot_unassignment")
      old_events = subscribe("enterprise_team.copilot.unassignment")

      enterprise_team_assignment = EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: :copilot)
      enterprise_team.destroy

      expected_payload = {
        enterprise_team_id: enterprise_team.id,
        enterprise_team: enterprise_team.slug,
        business: @business.name,
        business_id: @business.id,
      }

      event = new_events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot_unassignment", event.name
      assert_equal expected_payload, event.payload

      expected_payload = {
        id: enterprise_team.id
      }

      event = old_events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.unassignment", event.name
      assert_equal expected_payload, event.payload
    end

    test "enterprise_team.destroy is emitted when team is deleted" do
      expected_payload = {
        business_id: @team.business.id,
        business: @team.business.slug,
        enterprise_team_id: @team.id,
        enterprise_team: @team.slug,
      }

      events = subscribe("enterprise_team.destroy")
      @team.destroy

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.destroy", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "direct_memberships_enabled?" do
    test "returns false if idp group connected" do
      refute(@team.direct_memberships_enabled?)
    end

    test "returns true if no idp group connected" do
      @enterprise_team_group_mapping.destroy
      assert(@team.direct_memberships_enabled?)
    end
  end

  context "destroy_memberships_for" do
    test "removes memberships skips if full plan, non EMU and no FF enabled", skip_with_all_emus: true do
      business = GitHub.single_business_environment? ? @business : create(:business)
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)
      user = create(:user, business: business)
      team = create :enterprise_team, business: business
      team.enterprise_team_memberships.create!(user_id: user.id)

      EnterpriseTeam.destroy_memberships_for(user_ids: [user.id], business_id: business.id)

      refute_empty EnterpriseTeamMembership.joins(:enterprise_team).where(
        enterprise_teams: { business_id: business.id },
        enterprise_team_memberships: { user_id: [user.id] }
      )
    end unless GitHub.single_business_environment?  # GHES is all or nothing Enterprise Teams x ESM

    test "removes memberships on full plan with FF" do
      business = GitHub.single_business_environment? ? @business : create(:business)
      user = create(:user, business: business)
      team = create :enterprise_team, business: business
      team.enterprise_team_memberships.create!(user_id: user.id)

      EnterpriseTeam.destroy_memberships_for(user_ids: [user.id], business_id: business.id)

      assert_empty EnterpriseTeamMembership.joins(:enterprise_team).where(
        enterprise_teams: { business_id: business.id },
        enterprise_team_memberships: { user_id: [user.id] }
      )
    end

    test "removes memberships on basic plan, no FF needed" do
      business = create(:business)
      business.update(seats_plan_type: :basic)
      user = create(:user, business: business)
      team = create :enterprise_team, business: business

      EnterpriseTeamAssignment.create!(enterprise_team: team, assignment_type: :copilot)
      team.enterprise_team_memberships.create!(user_id: user.id)

      events = subscribe("enterprise_team.copilot.update")
      EnterpriseTeam.destroy_memberships_for(user_ids: [user.id], business_id: business.id)

      expected_payload = {
        id: team.id,
      }
      assert_equal 1, events.count
      event = events.pop
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal expected_payload, event.payload
      assert_empty EnterpriseTeamMembership.joins(:enterprise_team).where(
        enterprise_teams: { business_id: business.id },
        enterprise_team_memberships: { user_id: [user.id] }
      )
    end unless GitHub.single_business_environment?

    test "removes memberships on full plan EMU" do
      business = @business
      user = create(:user, business: business)
      team = create :enterprise_team, business: business
      team.enterprise_team_memberships.create!(user_id: user.id)

      EnterpriseTeam.destroy_memberships_for(user_ids: [user.id], business_id: business.id)

      assert_empty EnterpriseTeamMembership.joins(:enterprise_team).where(
        enterprise_teams: { business_id: business.id },
        enterprise_team_memberships: { user_id: [user.id] }
      )
    end
  end

  context "enabled_for_organizations?" do
    # we short-circuited the check, this will now return false https://github.com/github/Identity-Teams/issues/1379
    test "returns true with all enabled feature flags for an EMU business" do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      GitHub.stubs(:esm_enabled?).returns(false)
      GitHub.flipper[:enterprise_teams_enabled_for_organizations].enable(@business)

      refute EnterpriseTeam.enabled_for_organizations?(business: @business)
    end

    # we short-circuited the check, this will now return false https://github.com/github/Identity-Teams/issues/1379
    test "returns true when enabled_for_organizations for a non-basic EMU" do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      GitHub.stubs(:esm_enabled?).returns(false)
      GitHub.flipper[:enterprise_teams_enabled_for_organizations].enable(@business)

      refute EnterpriseTeam.enabled_for_organizations?(business: @business)
    end

    # we short-circuited the check, this will now return false https://github.com/github/Identity-Teams/issues/1379
    test "returns true for security center private beta business when private beta flag is on" do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      GitHub.stubs(:esm_enabled?).returns(false)
      GitHub.flipper[:security_center_private_beta].enable(@business)
      GitHub.flipper[:enterprise_teams_enabled_for_organizations].disable(@business)
      GitHub.flipper[:enterprise_teams_enabled_for_organizations_private_beta].enable

      refute EnterpriseTeam.enabled_for_organizations?(business: @business)
    end

    test "returns false for business not in the security center private beta when private beta flag is on" do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      if GitHub.single_business_environment?
        GitHub.stubs(:esm_enabled?).returns(false)
      else
        GitHub.flipper[:security_center_private_beta].disable(@business)
        GitHub.flipper[:enterprise_teams_enabled_for_organizations].disable(@business)
        GitHub.flipper[:enterprise_teams_enabled_for_organizations_private_beta].enable
      end

      refute EnterpriseTeam.enabled_for_organizations?(business: @business)
    end

    # we short-circuited the check, this will now return false https://github.com/github/Identity-Teams/issues/1379
    test "returns true when enabled_for_organizations for a non-basic non EMU", skip_with_all_emus: true do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      business = create :business
      GitHub.flipper[:enterprise_teams_enabled_for_organizations].enable(business)

      refute EnterpriseTeam.enabled_for_organizations?(business: business)
    end unless GitHub.single_business_environment?

    test "returns false when basic business" do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      business = create :business
      business.update(seats_plan_type: :basic)
      GitHub.flipper[:enterprise_teams_enabled_for_organizations].enable(business)

      refute EnterpriseTeam.enabled_for_organizations?(business: business)
    end unless GitHub.single_business_environment?

    test "returns false when enterprise_teams_enabled_for_organizations is disabled" do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      if GitHub.single_business_environment?
        GitHub.stubs(:esm_enabled?).returns(false)
      else
        GitHub.flipper[:enterprise_teams_enabled_for_organizations].disable(@business)
      end

      refute EnterpriseTeam.enabled_for_organizations?(business: @business)
    end

    test "returns true on GHES when esm_enabled? is true" do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      GitHub.stubs(:esm_enabled?).returns(true)
      assert EnterpriseTeam.enabled_for_organizations?(business: @business)
    end if GitHub.enterprise?
  end

  context "enabled_for_organization_security_manager?" do
    test "returns true on GHES when esm_enabled? is true" do
      GitHub.stubs(:esm_enabled?).returns(true)
      assert EnterpriseTeam.enabled_for_organization_security_manager?(@business)
    end if GitHub.enterprise?

    test "returns false if org sync is disabled" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)
      refute EnterpriseTeam.enabled_for_organization_security_manager?(@business)
    end

    test "returns true if enterprise_teams_security_manager_sync ff and enabled_for_organizations are enabled" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      @business.enable_feature(:enterprise_teams_security_manager_sync)
      assert EnterpriseTeam.enabled_for_organization_security_manager?(@business)
    end

    test "returns true for security center private beta business when private beta flag is on" do
      EnterpriseTeam.expects(:enabled_for_organizations?).at_least_once.returns(true)
      GitHub.flipper[:security_center_private_beta].enable(@business)
      GitHub.flipper[:enterprise_teams_security_manager_sync].disable(@business)
      GitHub.flipper[:enterprise_teams_security_manager_sync_private_beta].enable

      assert EnterpriseTeam.enabled_for_organization_security_manager?(@business)
    end

    test "returns false for business not in the security center private beta when private beta flag is on" do
      EnterpriseTeam.expects(:enabled_for_organizations?).at_least_once.returns(true)
      if GitHub.single_business_environment?
        GitHub.stubs(:esm_enabled?).returns(false)
      else
        GitHub.flipper[:security_center_private_beta].disable(@business)
        GitHub.flipper[:enterprise_teams_security_manager_sync].disable(@business)
        GitHub.flipper[:enterprise_teams_security_manager_sync_private_beta].enable
      end

      refute EnterpriseTeam.enabled_for_organization_security_manager?(@business)
    end
  end

  context "disabled_for_organization?" do
    test "returns true when organization is in the disabled list" do
      GitHub.flipper[:enterprise_teams_disabled_for_organizations].enable(@organization)

      assert EnterpriseTeam.disabled_for_organization?(organization: @organization)
    end

    test "returns false when organization is not in the disabled list" do
      GitHub.flipper[:enterprise_teams_disabled_for_organizations].disable(@organization)

      refute EnterpriseTeam.disabled_for_organization?(organization: @organization)
    end

    test "returns false when organization is nil" do
      refute EnterpriseTeam.disabled_for_organization?(organization: nil)
    end
  end

  context "#can_sync_to_organizations?" do
    context "when all is well" do
      test "it returns true" do
        assert_predicate @team, :can_sync_to_organizations?
      end
    end

    context "when all is not well" do
      test "and there are too many members" do
        EnterpriseTeam.stubs(:max_sync_members).returns(1)
        refute_predicate @team, :can_sync_to_organizations?
      end

      test "and we've synced to too many orgs", feature_disabled: :enterprise_team_org_sync_bypass_limit do
        # create a 2nd GHAS enabled org
        organization2 = create :organization, business: @business
        repo2 = create :private_repository, owner: organization2
        create(:repository_security_center_config, repository: repo2, ghas_enabled: true)

        # can only sync to max 1 org
        EnterpriseTeam.stubs(:max_sync_organizations).returns(1)
        refute_predicate @team, :can_sync_to_organizations?
      end
    end
  end

  context "#can_sync_to_organizations_member_check?" do
    test "returns true when members are within limit" do
      assert_predicate @team, :can_sync_to_organizations_member_check?
    end

    test "returns false when there are too many members" do
      EnterpriseTeam.stubs(:max_sync_members).returns(1)
      refute_predicate @team, :can_sync_to_organizations_member_check?
    end
  end

  context "member?" do
    context "when idp group is connected" do
      test "returns if user is in group" do
        team = create :enterprise_team, business: @business
        external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 5)
        enterprise_team_group_mapping = EnterpriseTeamGroupMapping.create!(enterprise_team: team, external_group: external_group)

        assert team.member?(external_group.members.first.external_identity.user)
        refute team.member?(create(:user))
      end
    end

    context "when no idp group connected" do
      test "returns if user is in group" do
        @enterprise_team_group_mapping.destroy

        user1 = create(:user)
        user2 = create(:user)

        @team.enterprise_team_memberships.create(user_id: user1.id)

        assert @team.member?(user1)
        refute @team.member?(user2)
      end
    end
  end

  context "member_user_ids" do
    context "when idp group is connected" do
      test "returns array of external identity IDs when a team has members in it" do
        assert_same_elements(@external_group.member_user_ids, @team.member_user_ids)
      end

      test "returns empty array for teams with no members" do
        empty_team = create :enterprise_team, business: @business
        empty_external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 0)
        empty_enterprise_team_group_mapping = EnterpriseTeamGroupMapping.create!(enterprise_team: empty_team, external_group: empty_external_group)

        assert_empty(empty_team.member_user_ids)
      end

      test "does not return suspended users" do
        team = create :enterprise_team, business: @business
        external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 5)
        enterprise_team_group_mapping = EnterpriseTeamGroupMapping.create!(enterprise_team: team, external_group: external_group)
        external_group.members.first.external_identity.disable

        assert_equal 4, team.member_user_ids.count
      end
    end

    context "when no idp group connected" do
      test "returns array of user_ids from enterprise_team_memberships" do
        @enterprise_team_group_mapping.destroy

        user1 = create(:user)
        user2 = create(:user)

        @team.enterprise_team_memberships.create(user_id: user1.id)
        @team.enterprise_team_memberships.create(user_id: user2.id)

        assert_same_elements([user1.id, user2.id], @team.member_user_ids)
      end

      test "returns empty array when no enterprise_team_memberships" do
        @enterprise_team_group_mapping.destroy
        assert_empty(@team.member_user_ids)
      end
    end

    test "when no group_mappings or direct memberships" do
      @enterprise_team_group_mapping.destroy
      assert_empty(@team.member_user_ids)
    end
  end

  context "member_count" do
    context "when idp group is connected" do
      test "returns count of external group members" do
        assert_equal(2, @team.member_count)
      end
    end

    context "when no idp group connected" do
      test "returns count of direct memberships enterprise_team_memberships" do
        @enterprise_team_group_mapping.destroy

        user1 = create(:user)
        user2 = create(:user)

        @team.enterprise_team_memberships.create(user_id: user1.id)
        @team.enterprise_team_memberships.create(user_id: user2.id)

        assert_equal(2, @team.member_count)
      end
    end

    test "when no group_mappings or direct memberships" do
      @enterprise_team_group_mapping.destroy
      assert_empty(@team.member_user_ids)
    end
  end

  context "team names" do
    test "strips leading & trailing whitespace from team names" do
      team = create(:enterprise_team, business: @business, name: "  spaces  ")
      assert_equal team.name, "spaces"
    end

    test "names are unique, including non-deleted" do
      team = build(:enterprise_team, business: @business, name: @team.name)
      refute team.save
      assert_equal 1, team.errors.full_messages.size
      assert_match(/must be unique for this business/, team.errors.full_messages.first)
    end

    test "names are unique, excluding deleted" do
      create(:enterprise_team, business: @business, name: "existing", deleted_at: DateTime.now)
      assert build(:enterprise_team, business: @business, name: "existing").save
    end
  end

  context "scopes" do
    test "returns active mappings" do
      assert_includes @business.enterprise_teams.active, @team
      @team.update(deleted_at: Time.now)
      refute_includes @business.enterprise_teams.active, @team
    end

    test "returns deleted mappings" do
      @team.update(deleted_at: Time.now)
      assert_includes @business.enterprise_teams.deleted, @team
    end

    test "returns assignment types" do
      copilot_type = EnterpriseTeamAssignment.create!(enterprise_team: @team, assignment_type: :copilot)

      assert_same_elements [copilot_type],  @team.enterprise_team_assignments
    end

    test "returns active enterprise team group mappings" do
      new_external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 3)
      etgm = EnterpriseTeamGroupMapping.create!(enterprise_team: @team, external_group: new_external_group)
      etgm.update(deleted_at: Time.now)
      team_mappings = @team.enterprise_team_group_mappings.reload

      assert_equal 1, team_mappings.count
      refute_includes team_mappings, etgm
      assert_includes team_mappings, @enterprise_team_group_mapping
    end

    test "returns enterprise team organization mappings" do
      EnterpriseTeamOrganizationMapping.create!(enterprise_team: @team, organization: @organization)
      assert_equal 1, @team.enterprise_team_organization_mappings.count
    end

    test "returns direct memberships" do
      @enterprise_team_group_mapping.soft_delete
      membership1 = EnterpriseTeamMembership.create!(enterprise_team: @team, user: @owner)
      user = create_user_with_ext_id
      membership2 = EnterpriseTeamMembership.create!(enterprise_team: @team, user: user)

      assert_same_elements [membership1, membership2],  @team.enterprise_team_memberships
    end

    context ".exclude_having_assignment" do
      test "excludes teams with the given assignment type" do
        EnterpriseTeamAssignment.create!(enterprise_team: @team, assignment_type: :security_manager)
        assert_empty @business.enterprise_teams.exclude_having_assignment(:security_manager).to_a
      end

      test "excludes teams with the given assignment type even if they have other assignment types" do
        EnterpriseTeamAssignment.create!(enterprise_team: @team, assignment_type: :copilot)
        EnterpriseTeamAssignment.create!(enterprise_team: @team, assignment_type: :security_manager)
        assert_empty @business.enterprise_teams.exclude_having_assignment(:security_manager).to_a
      end

      test "includes teams that have only assignments that aren't the given assignment type" do
        EnterpriseTeamAssignment.create!(enterprise_team: @team, assignment_type: :copilot)
        assert_same_elements [@team], @business.enterprise_teams.exclude_having_assignment(:security_manager).to_a
      end

      test "includes teams that have no assignments" do
        assert_empty EnterpriseTeamAssignment.all
        assert_same_elements [@team], @business.enterprise_teams.exclude_having_assignment(:security_manager).to_a
      end

      test "includes teams when an unknown assignment type is given" do
        EnterpriseTeamAssignment.create!(enterprise_team: @team, assignment_type: :copilot)
        EnterpriseTeamAssignment.create!(enterprise_team: @team, assignment_type: :security_manager)
        assert_same_elements [@team], @business.enterprise_teams.exclude_having_assignment(:unknown).to_a
      end
    end
  end

  context "slug generation" do
    test "happens on create" do
      team = create(:enterprise_team, business: @business, name: "Pillow fighters")
      assert_equal "pillow-fighters", team.slug
    end

    test "crazy unicode stuff" do
      team = create(:enterprise_team, business: @business, name: "designers™")
      assert_equal "designers", team.slug
    end

    test "does not care about duplicates between different businesses" do
      @business2 = create :business
      team_from_different_org = create(:enterprise_team, name: "designers", business: @business2)
      team = create(:enterprise_team, business: @business, name: "designers")
      assert_equal "designers", team_from_different_org.slug
      assert_equal "designers", team.slug
    end unless GitHub.single_business_environment?

    test "avoids duplicates within the business" do
      team1 = create(:enterprise_team, business: @business, name: "designers on droogs")
      team2 = create(:enterprise_team, business: @business, name: "designers on-droogs")
      team3 = create(:enterprise_team, business: @business, name: "designers-on droogs")
      assert_equal "designers-on-droogs", team1.slug
      assert_equal "designers-on-droogs-1", team2.slug
      assert_equal "designers-on-droogs-2", team3.slug
    end

    test "does not do anything if the name has not changed" do
      team = create(:enterprise_team, business: @business, name: "designers")
      team.reload
      team.expects(:generate_unique_slug).never
      team.save!
    end

    test "regenerates the slug when the name changes" do
      team = create(:enterprise_team, business: @business, name: "designers")
      team.name = "graphical fairy peoples - vice squad"
      team.save!
      assert_equal "graphical-fairy-peoples-vice-squad", team.slug
    end

    test "does not change the slug if the team name is lowercased (with no other changes)" do
      team = create(:enterprise_team, business: @business, name: "DotCom")
      assert_equal "dotcom", team.slug
      team.name = "dotcom"
      team.save!
      assert_equal "dotcom", team.slug
    end

    test "periods get stripped from slugs" do
      team = create(:enterprise_team, business: @business, name: ".com")
      assert_equal ".com", team.name
      assert_equal "com", team.slug
    end

    test "leading/trailing spaces get stripped from slug" do
      team = create(:enterprise_team, business: @business, name: "  has spaces ")
      assert_equal team.slug, "has-spaces"
    end

    test "generates nice fake slugs when the team name is all unicode" do
      team = create(:enterprise_team, business: @business, name: "£")
      assert_equal "team", team.slug

      team = create(:enterprise_team, business: @business, name: "¢")
      assert_equal "team-1", team.slug

      team = create(:enterprise_team, business: @business, name: "¥")
      assert_equal "team-2", team.slug
    end
  end

  context "active_record callbacks" do
    test "does not call instrument_update after create" do
      team = build(:enterprise_team, business: @business)
      team.expects(:instrument_update).never
      team.save!
    end

    test "do not call instrument_update after updating just the name" do
      @team.expects(:instrument_update).never
      @team.update(name: "new name")
    end

    test "does not call instrument_update after destroy" do
      @team.expects(:instrument_update).never
      @team.destroy
    end
  end

  context "#copilot_enterprise_team" do
    test "returns true when the team is a copilot team" do
      team = create :enterprise_team, business: @business
      team_assignment = EnterpriseTeamAssignment.create!(enterprise_team: team, assignment_type: :copilot)
      assert_predicate team, :copilot_enterprise_team?
    end

    test "returns false when the team is not a copilot team" do
      refute_predicate @team, :copilot_enterprise_team?
    end
  end

  context "#bulk_add_members" do
    test "adds multiple users to a team and instruments an update" do
      team = create :enterprise_team, business: @business
      EnterpriseTeamAssignment.create!(enterprise_team: team, assignment_type: :copilot)
      emu0 = create_user_with_ext_id
      emu1 = create_user_with_ext_id

      events = subscribe("enterprise_team.copilot.update")
      team.bulk_add_members(users: [emu0, emu1])

      assert_equal 2, team.member_user_ids.length
      assert team.member_user_ids.include?(emu0.id)
      assert team.member_user_ids.include?(emu1.id)

      expected_payload = {
        id: team.id,
      }
      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal expected_payload, event.payload
    end

    test "can handle nils" do
      team = create :enterprise_team, business: @business
      emu0 = create_user_with_ext_id
      emu1 = create_user_with_ext_id

      team.bulk_add_members(users: [emu0, nil, emu1])

      assert_equal 2, team.member_user_ids.length
      assert team.member_user_ids.include?(emu0.id)
      assert team.member_user_ids.include?(emu1.id)
    end

    test "can handle suspended users" do
      GitHub.flipper[:reject_add_suspended_users].enable
      team = create :enterprise_team, business: @business
      emu0 = create_user_with_ext_id
      emu1 = create_user_with_ext_id
      emu2 = create_user_with_ext_id
      emu2.update!(suspended_at: Time.now - 1.minute)

      team.bulk_add_members(users: [emu0, emu1, emu2])

      assert_equal 2, team.member_user_ids.length
      assert team.member_user_ids.include?(emu0.id)
      assert team.member_user_ids.include?(emu1.id)
      refute team.member_user_ids.include?(emu2.id)
      refute EnterpriseTeamMembership.where(user_id: emu2.id).exists?
    end

    test "does nothing for an IdP managed team" do
      emu0 = create_user_with_ext_id
      emu1 = create_user_with_ext_id
      @team.bulk_add_members(users: [emu0, emu1])

      assert_equal @external_group.members.length, @team.member_user_ids.length
      refute @team.member_user_ids.include?(emu0.id)
      refute @team.member_user_ids.include?(emu1.id)
    end

    test "does not attempt insert of existing members" do
      team = create :enterprise_team, business: @business
      emu0 = create_user_with_ext_id
      emu1 = create_user_with_ext_id

      team.bulk_add_members(users: [emu0])
      EnterpriseTeamMembership.expects(:insert_all).with(
        [{ enterprise_team_id: team.id, user_id: emu1.id }]
      )
      team.bulk_add_members(users: [emu0, emu1])
    end
  end

  context "#instrument team update event" do
    test "emits enterprise_team.copilot.update event when the team is a copilot team" do
      team = create :copilot_enterprise_team_assignment

      events = subscribe("enterprise_team.copilot.update")

      team.instrument_update

      expected_payload = {
        id: team.id,
      }

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal expected_payload, event.payload
    end unless GitHub.single_business_environment? # No copilot for GHES

    test "do not emit enterprise_team.copilot.update event when the team has no assignment" do
      events = subscribe("enterprise_team.copilot.update")
      @team.instrument_update

      event = events.pop
      assert_nil event
    end

    test "emits enterprise_team.update event when the team has no assignments" do
      events = subscribe("enterprise_team.update")

      @team.instrument_update

      expected_payload = {
        id: @team.id,
      }

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.update", event.name
      assert_equal expected_payload, event.payload
    end

    test "emits enterprise_team.update event when the team has assignments" do
      EnterpriseTeamAssignment.create!(enterprise_team: @team, assignment_type: :security_manager)

      events = subscribe("enterprise_team.update")

      @team.instrument_update

      expected_payload = {
        id: @team.id,
      }

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.update", event.name
      assert_equal expected_payload, event.payload
    end

    test "does not emit enterprise_team.update event if feature flag is disabled" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)
      events = subscribe("enterprise_team.update")

      @team.instrument_update

      event = events.pop
      assert_nil event
    end unless GitHub.single_business_environment?  # GHES is all or nothing Enterprise Teams x ESM
  end

  context "#instrument add member event" do
    test "emits enterprise_team.add_member event when a direct membership is added" do
      user = create_user_with_ext_id
      team = create :enterprise_team, business: @business

      expected_payload = {
        user_id: user.id,
        user: user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: team.id,
        enterprise_team: team.slug,
      }

      events = subscribe("enterprise_team.add_member")
      team.enterprise_team_memberships.create!(user_id: user.id)

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.add_member", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "#instrument remove member event" do
    test "emits enterprise_team.remove_member event when a direct membership is removed" do
      user = create_user_with_ext_id
      team = create :enterprise_team, business: @business

      team.enterprise_team_memberships.create!(user_id: user.id)

      expected_payload = {
        user_id: user.id,
        user: user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: team.id,
        enterprise_team: team.slug,
      }

      events = subscribe("enterprise_team.remove_member")
      EnterpriseTeam.destroy_memberships_for(user_ids: [user.id], business_id: @business.id)

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.remove_member", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "#instrument team rename event" do

    test "emits enterprise_team.rename event when the name is modified" do
      team = create :enterprise_team, business: @business, name: "Identity"

      expected_payload = {
        name: "Tnt 2024",
        name_was: "Identity",
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: team.id,
        enterprise_team: "tnt-2024",
      }

      events = subscribe("enterprise_team.rename")
      team.update!(name: "Tnt 2024")

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.rename", event.name
      assert_equal expected_payload, event.payload
    end

    test "does not emit enterprise_team.rename event when the name has not changed" do
      team = create :enterprise_team, business: @business, name: "Identity"

      events = subscribe("enterprise_team.rename")
      team.update!(name: "Identity")

      event = events.pop
      assert_nil event
    end
  end

  context "#check_sync_to_organizations" do
    test "cannot enable org sync if MAX_SYNC_MEMBERS exceeded" do
      EnterpriseTeam.stub(:max_sync_members, 0) do
        @team.sync_to_organizations = "all"
        exception = assert_raises ActiveRecord::RecordInvalid do
          @team.save!
        end
        assert_equal "Validation failed: Sync to organizations - Cannot sync to all GHAS enabled organizations if Enterprise Team has more than #{EnterpriseTeam.max_sync_members} members or Business has over #{EnterpriseTeam.max_sync_organizations} GHAS enabled organizations", exception.message
      end
    end

    test "cannot enable org sync MAX_SYNC_ORGANIZATIONS exceeded" do
      GitHub.flipper[:enterprise_team_org_sync_bypass_limit].disable(@business)
      EnterpriseTeam.stub(:max_sync_organizations, 0) do
        @team.sync_to_organizations = "all"
        exception = assert_raises ActiveRecord::RecordInvalid do
          @team.save!
        end
        assert_equal "Validation failed: Sync to organizations - Cannot sync to all GHAS enabled organizations if Enterprise Team has more than #{EnterpriseTeam.max_sync_members} members or Business has over #{EnterpriseTeam.max_sync_organizations} GHAS enabled organizations", exception.message
      end
    end

    test "can stay enabled if limits reached (can rename team)" do
      team = create :enterprise_team, business: @business, name: "some name"
      team.sync_to_organizations = "all"
      team.save!

      GitHub.flipper[:enterprise_team_org_sync_bypass_limit].disable(@business)
      EnterpriseTeam.stub(:max_sync_members, 0) do
        EnterpriseTeam.stub(:max_sync_organizations, 0) do
          team.name = "new name"
          team.save!
        end
      end
    end

    test "succeeds when MAX_SYNC_MEMBERS and MAX_SYNC_ORGANIZATIONS not exceeded" do
      EnterpriseTeamMembership.create!(enterprise_team: @team, user_id: @owner.id)
      @team.sync_to_organizations = "all"
      @team.save!
      assert_equal "all", @team.sync_to_organizations
    end
  end

  context "#all_teams_for" do
    test "returns all teams for a user within a business, exclude suspended users" do
      emu = create_user_with_ext_id

      idp_team = create :enterprise_team, business: @business
      external_group = create(:external_group, business: @business)
      EnterpriseTeamGroupMapping.create!(enterprise_team: idp_team, external_group: external_group)
      ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: emu.external_identities.first)

      direct_team = create :enterprise_team, business: @business
      direct_team.bulk_add_members(users: [emu])

      assert_same_elements [idp_team, direct_team], EnterpriseTeam.all_teams_for(@business, emu)
      assert_same_elements [idp_team.id, direct_team.id], EnterpriseTeam.all_team_ids_for(@business, emu)

      emu.external_identities.first.disable
      EnterpriseTeam.destroy_memberships_for(user_ids: [emu.id], business_id: @business.id)
      assert_same_elements [], EnterpriseTeam.all_teams_for(@business, emu)
    end

    test "returns all teams for a user within a business, exclude deleted users" do
      emu = create_user_with_ext_id

      idp_team = create :enterprise_team, business: @business
      external_group = create(:external_group, business: @business)
      EnterpriseTeamGroupMapping.create!(enterprise_team: idp_team, external_group: external_group)
      ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: emu.external_identities.first)

      direct_team = create :enterprise_team, business: @business
      direct_team.bulk_add_members(users: [emu])

      assert_same_elements [idp_team, direct_team], EnterpriseTeam.all_teams_for(@business, emu)
      assert_same_elements [idp_team.id, direct_team.id], EnterpriseTeam.all_team_ids_for(@business, emu)

      emu.external_identities.first.mark_deleted
      EnterpriseTeam.destroy_memberships_for(user_ids: [emu.id], business_id: @business.id)
      assert_same_elements [], EnterpriseTeam.all_teams_for(@business, emu)
    end

    test "returns all teams for a user within a business, excluded deleted group" do
      emu = create_user_with_ext_id

      idp_team = create :enterprise_team, business: @business
      external_group = create(:external_group, business: @business)
      EnterpriseTeamGroupMapping.create!(enterprise_team: idp_team, external_group: external_group)
      ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: emu.external_identities.first)

      direct_team = create :enterprise_team, business: @business
      direct_team.bulk_add_members(users: [emu])

      assert_same_elements [idp_team, direct_team], EnterpriseTeam.all_teams_for(@business, emu)
      assert_same_elements [idp_team.id, direct_team.id], EnterpriseTeam.all_team_ids_for(@business, emu)

      perform_enqueued_jobs only: [ClearEnterpriseTeamGroupMappingsJob] do
        external_group.mark_group_deleted
      end
      assert_same_elements [direct_team], EnterpriseTeam.all_teams_for(@business, emu)
    end

    test "returns all teams for a user within a business, excluded deleted group mapping" do
      emu = create_user_with_ext_id

      idp_team = create :enterprise_team, business: @business
      external_group = create(:external_group, business: @business)
      mapping = EnterpriseTeamGroupMapping.create!(enterprise_team: idp_team, external_group: external_group)
      ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: emu.external_identities.first)

      direct_team = create :enterprise_team, business: @business
      direct_team.bulk_add_members(users: [emu])

      assert_same_elements [idp_team, direct_team], EnterpriseTeam.all_teams_for(@business, emu)
      assert_same_elements [idp_team.id, direct_team.id], EnterpriseTeam.all_team_ids_for(@business, emu)

      mapping.soft_delete
      assert_same_elements [direct_team], EnterpriseTeam.all_teams_for(@business, emu)
    end

    test "returns all teams for a user within a business, excluded team from other business" do
      business2 = create(:business)
      business1 = create(:business)

      user = create(:user)
      business1.add_owner(user, actor: business1.admins.first)
      business2.add_owner(user, actor: business2.admins.first)

      direct_team1 = create :enterprise_team, business: business1
      direct_team1.bulk_add_members(users: [user])

      direct_team2 = create :enterprise_team, business: business2
      direct_team2.bulk_add_members(users: [user])

      assert_same_elements [direct_team1], EnterpriseTeam.all_teams_for(business1, user)
      assert_same_elements [direct_team2], EnterpriseTeam.all_teams_for(business2, user)
    end unless GitHub.single_business_environment?
  end

  context "#all_visible_teams_for" do
    test "returns all teams for a user within a business, exclude suspended users" do
      emu = create_user_with_ext_id

      idp_team = create :enterprise_team, business: @business
      external_group = create(:external_group, business: @business)
      EnterpriseTeamGroupMapping.create!(enterprise_team: idp_team, external_group: external_group)
      ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: emu.external_identities.first)

      direct_team = create :enterprise_team, business: @business
      direct_team.bulk_add_members(users: [emu])

      assert_same_elements [idp_team, direct_team], EnterpriseTeam.all_visible_teams_for(emu, business_ids: [@business.id])
      assert_same_elements [idp_team.id, direct_team.id], EnterpriseTeam.all_visible_team_ids_for(emu, business_ids: [@business.id])

      emu.external_identities.first.disable
      EnterpriseTeam.destroy_memberships_for(user_ids: [emu.id], business_id: @business.id)
      assert_same_elements [], EnterpriseTeam.all_visible_teams_for(emu)
    end

    test "returns all teams for a user within a business, exclude deleted users" do
      emu = create_user_with_ext_id

      idp_team = create :enterprise_team, business: @business
      external_group = create(:external_group, business: @business)
      EnterpriseTeamGroupMapping.create!(enterprise_team: idp_team, external_group: external_group)
      ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: emu.external_identities.first)

      direct_team = create :enterprise_team, business: @business
      direct_team.bulk_add_members(users: [emu])

      assert_same_elements [idp_team, direct_team], EnterpriseTeam.all_visible_teams_for(emu, business_ids: [@business.id])
      assert_same_elements [idp_team.id, direct_team.id], EnterpriseTeam.all_visible_team_ids_for(emu, business_ids: [@business.id])

      emu.external_identities.first.mark_deleted
      EnterpriseTeam.destroy_memberships_for(user_ids: [emu.id], business_id: @business.id)
      assert_same_elements [], EnterpriseTeam.all_visible_teams_for(emu)
      assert_same_elements [], EnterpriseTeam.all_visible_team_ids_for(emu)
    end

    test "returns all teams for a user within a business, excluded deleted group" do
      emu = create_user_with_ext_id

      idp_team = create :enterprise_team, business: @business
      external_group = create(:external_group, business: @business)
      EnterpriseTeamGroupMapping.create!(enterprise_team: idp_team, external_group: external_group)
      ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: emu.external_identities.first)

      direct_team = create :enterprise_team, business: @business
      direct_team.bulk_add_members(users: [emu])

      assert_same_elements [idp_team, direct_team], EnterpriseTeam.all_visible_teams_for(emu, business_ids: [@business.id])
      assert_same_elements [idp_team.id, direct_team.id], EnterpriseTeam.all_visible_team_ids_for(emu, business_ids: [@business.id])

      perform_enqueued_jobs only: [ClearEnterpriseTeamGroupMappingsJob] do
        external_group.mark_group_deleted
      end

      assert_same_elements [direct_team], EnterpriseTeam.all_visible_teams_for(emu)
      assert_same_elements [direct_team.id], EnterpriseTeam.all_visible_team_ids_for(emu)
    end

    test "returns all teams for a user within a business, excluded deleted group mapping" do
      emu = create_user_with_ext_id

      idp_team = create :enterprise_team, business: @business
      external_group = create(:external_group, business: @business)
      mapping = EnterpriseTeamGroupMapping.create!(enterprise_team: idp_team, external_group: external_group)
      ExternalIdentityGroupMembership.create(external_group: external_group, external_identity: emu.external_identities.first)

      direct_team = create :enterprise_team, business: @business
      direct_team.bulk_add_members(users: [emu])

      assert_same_elements [idp_team, direct_team], EnterpriseTeam.all_visible_teams_for(emu, business_ids: [@business.id])
      assert_same_elements [idp_team.id, direct_team.id], EnterpriseTeam.all_visible_team_ids_for(emu, business_ids: [@business.id])

      mapping.soft_delete

      assert_same_elements [direct_team], EnterpriseTeam.all_visible_teams_for(emu)
      assert_same_elements [direct_team.id], EnterpriseTeam.all_visible_team_ids_for(emu)
    end

    test "returns all teams for a user within a business, excluded team from other business" do
      GitHub.flipper[:unaffiliated_user_accounts].enable
      business2 = create(:business)
      business1 = create(:business)

      user = create(:user)
      business1.add_owner(user, actor: business1.admins.first)
      business2.add_user_accounts([user.id], business_roles_bitfield: 0)

      direct_team1 = create :enterprise_team, business: business1
      direct_team1.bulk_add_members(users: [user])

      direct_team2 = create :enterprise_team, business: business2
      direct_team2.bulk_add_members(users: [user])

      assert_same_elements [direct_team1, direct_team2], EnterpriseTeam.all_visible_teams_for(user)
      assert_same_elements [direct_team1], EnterpriseTeam.all_visible_teams_for(user, business_ids: [business1.id])
      assert_same_elements [direct_team2], EnterpriseTeam.all_visible_teams_for(user, business_ids: [business2.id])
    end unless GitHub.single_business_environment?

    test "returns all teams when business is nil" do
      business2 = create(:business)
      business1 = create(:business)

      user = create(:user)
      business1.add_owner(user, actor: business1.admins.first)
      business2.add_owner(user, actor: business2.admins.first)

      direct_team1 = create :enterprise_team, business: business1
      direct_team1.bulk_add_members(users: [user])

      direct_team2 = create :enterprise_team, business: business2
      direct_team2.bulk_add_members(users: [user])

      assert_same_elements [direct_team1, direct_team2], EnterpriseTeam.all_visible_teams_for(user)
      assert_same_elements [direct_team1.id, direct_team2.id], EnterpriseTeam.all_visible_team_ids_for(user)
    end unless GitHub.single_business_environment?
  end

  context "integration" do
    test "adds enterprise team with users to orgs" do
      @business.update(seats_plan_type: :full)
      users = (1..5).to_a.map { create_user_with_ext_id }
      @business.add_user_accounts(users.pluck(:id), business_roles_bitfield: 0)
      orgs = (1..10).to_a.map { |i| create(:organization, login: "test-add-org-#{i}", business: @business) }
      synced_enterprise_team = create :enterprise_team, business: @business, sync_to_organizations: "all"
      synced_enterprise_team.bulk_add_members(users: users)
      orgs.each do |o|
        org_team = create :team, organization: o
        EnterpriseTeamOrganizationMapping.create!(enterprise_team: synced_enterprise_team, organization: o, team: org_team)
      end
      assert_enqueued_jobs users.size, only: [AddToSearchIndexJob] do
        perform_enqueued_jobs(only: [EnterpriseTeamOrganizationMappingJob, EnterpriseTeamOrganizationReconciliationJob, EnterpriseTeamOrganizationReconciliationRunnerJob]) do
          EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: synced_enterprise_team.id)
        end
      end
      assert orgs.first.member?(users.first)
    end

    test "adds enterprise team with security managers to orgs" do
      GitHub.flipper[:enterprise_teams_disabled_for_organizations].disable
      @business.update(seats_plan_type: :full)
      @business.enable_feature(:enterprise_teams_security_manager_sync)
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      assert EnterpriseTeam.enabled_for_organization_security_manager?(@business)
      users = (1..5).to_a.map { create_user_with_ext_id }
      @business.add_user_accounts(users.pluck(:id), business_roles_bitfield: 0)
      orgs = (1..10).to_a.map { |i| create(:organization, login: "test-add-org-#{i}", business: @business) }
      synced_enterprise_team = create :enterprise_team, business: @business, sync_to_organizations: "all"
      synced_enterprise_team.bulk_add_members(users: users)
      orgs.each do |o|
        repo = create :private_repository, owner: o
        repo_config = create(:repository_security_center_config, repository: repo, ghas_enabled: true)
      end
      EnterpriseTeamAssignment.create!(enterprise_team: synced_enterprise_team, assignment_type: :security_manager)
      assert_enqueued_jobs users.size, only: [AddToSearchIndexJob] do
        perform_enqueued_jobs(only: [EnterpriseTeamOrganizationMappingJob, EnterpriseTeamOrganizationReconciliationJob, EnterpriseTeamOrganizationReconciliationRunnerJob]) do
          EnterpriseTeamOrganizationMappingJob.perform_now(synced_enterprise_team.id)
          EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: synced_enterprise_team.id)
        end
      end
      assert orgs.first.member?(users.first)
    end

    test "disables enterprise team with users from orgs" do
      @business.update(seats_plan_type: :full)
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      users = (1..5).to_a.map { create_user_with_ext_id }
      @business.add_user_accounts(users.pluck(:id), business_roles_bitfield: 0)
      orgs = (1..10).to_a.map { |i| create(:organization, login: "test-add-org-#{i}", business: @business) }
      synced_enterprise_team = create :enterprise_team, business: @business, sync_to_organizations: "all"
      synced_enterprise_team.bulk_add_members(users: users)
      orgs.each do |o|
        org_team = create :team, organization: o
        EnterpriseTeamOrganizationMapping.create!(enterprise_team: synced_enterprise_team, organization: o, team: org_team)
      end
      perform_enqueued_jobs(only: [EnterpriseTeamOrganizationMappingJob, EnterpriseTeamOrganizationReconciliationJob, EnterpriseTeamOrganizationReconciliationRunnerJob]) do
        EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: synced_enterprise_team.id)
      end
      assert_enqueued_jobs users.size, only: [AddToSearchIndexJob] do
        perform_enqueued_jobs(only: [EnterpriseTeamOrganizationMappingJob, EnterpriseTeamOrganizationReconciliationJob, EnterpriseTeamOrganizationReconciliationRunnerJob, OrganizationBulkRemoveMembersCleanupJob]) do
          synced_enterprise_team.update(sync_to_organizations: :disabled)
          EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: synced_enterprise_team.id)
        end
      end
      refute orgs.first.member?(users.first)
    end

    test "removes enterprise team with users from orgs" do
      @business.update(seats_plan_type: :full)
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      users = (1..5).to_a.map { create_user_with_ext_id }
      @business.add_user_accounts(users.pluck(:id), business_roles_bitfield: 0)
      orgs = (1..10).to_a.map { |i| create(:organization, login: "test-add-org-#{i}", business: @business) }
      synced_enterprise_team = create :enterprise_team, business: @business, sync_to_organizations: "all"
      synced_enterprise_team.bulk_add_members(users: users)
      orgs.each do |o|
        org_team = create :team, organization: o
        EnterpriseTeamOrganizationMapping.create!(enterprise_team: synced_enterprise_team, organization: o, team: org_team)
      end
      perform_enqueued_jobs(only: [EnterpriseTeamOrganizationMappingJob, EnterpriseTeamOrganizationReconciliationJob, EnterpriseTeamOrganizationReconciliationRunnerJob]) do
        EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: synced_enterprise_team.id)
      end
      assert_enqueued_jobs users.size, only: [AddToSearchIndexJob] do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob, EnterpriseTeamOrganizationMappingJob, EnterpriseTeamOrganizationReconciliationJob, EnterpriseTeamOrganizationReconciliationRunnerJob, OrganizationBulkRemoveMembersCleanupJob]) do
          # TODO: Currently calling EnterpriseTeam#destroy does not unassign all the members from synced
          # organizations. This needs to be looked at.
          synced_enterprise_team.update(sync_to_organizations: :disabled)
          EnterpriseTeamOrganizationReconciliationJob.perform_now(enterprise_team_id: synced_enterprise_team.id)
          synced_enterprise_team.destroy
        end
      end
      refute orgs.first.member?(users.first)
    end
  end

  private def create_user_with_ext_id
    if GitHub.single_business_environment?
      create :ghes_scim_user, business: @business
    else
      create :emu, business: @business
    end
  end
end
