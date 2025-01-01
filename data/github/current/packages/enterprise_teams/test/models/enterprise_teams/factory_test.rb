# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseTeamFactoryTest < GitHub::TestCase
  setup do
    @enterprise = create :business
    @business_admin = create :user

    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
    EnterpriseTeam.stubs(:enabled_for_organization_security_manager?).returns(true)
  end

  test "create a new team" do
    assert_difference "EnterpriseTeam.count", 1 do
      assert_no_difference "EnterpriseTeamAssignment.count" do
        assert_no_difference "EnterpriseTeamGroupMapping.count" do
          team = EnterpriseTeams::Factory.create_enterprise_team(enterprise: @enterprise, team_name: "Test Team", sync_to_organizations: "disabled", idp_group_id: nil, is_security_manager: false)
          assert_equal "Test Team", team.name
          assert_equal "disabled", team.sync_to_organizations
        end
      end
    end
  end

  test "create a new team with security manager assignment" do
    assert_difference ["EnterpriseTeam.count", "EnterpriseTeamAssignment.count"], 1 do
      team = EnterpriseTeams::Factory.create_enterprise_team(enterprise: @enterprise, team_name: "Test Team", sync_to_organizations: "all", idp_group_id: nil, is_security_manager: true)
      assert_equal "Test Team", team.name
      assert_equal "all", team.sync_to_organizations
      assert team.enterprise_team_assignments.exists?(assignment_type: "security_manager")
    end
  end

  test "does not create a new team with security manager assignment when sync to orgs is disabled" do
    assert_difference "EnterpriseTeam.count", 1 do
      assert_no_difference "EnterpriseTeamAssignment.count" do
        team = EnterpriseTeams::Factory.create_enterprise_team(enterprise: @enterprise, team_name: "Test Team", sync_to_organizations: "disabled", idp_group_id: nil, is_security_manager: true)
        assert_equal "Test Team", team.name
        assert_equal "disabled", team.sync_to_organizations
        assert_not team.enterprise_team_assignments.exists?(assignment_type: "security_manager")
      end
    end
  end

  test "create a new team with invalid parameters" do
    assert_no_difference "EnterpriseTeam.count" do
      assert_raises(ActiveRecord::RecordInvalid) do
        EnterpriseTeams::Factory.create_enterprise_team(enterprise: @enterprise, team_name: "", sync_to_organizations: "invalid", idp_group_id: nil, is_security_manager: false)
      end
    end
  end
end unless GitHub.enterprise?

class SCIMBasedEnterpriseTeamFactoryTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  fixtures do
    if GitHub.single_business_environment?
      setup_saml_auth_mode(with_scim: true)
      @enterprise = create :global_business
      @provider = @enterprise.external_provider
    else
      user = create(:emu, :owner, login: "org-admin")
      @enterprise = user.enterprise_managed_business
    end

    @owner = @enterprise.owners.first
    @org = create :organization, business: @enterprise, admin: @owner
    @external_group = create :external_group, :with_members, business: @enterprise, number_of_members: 2
    @external_group_users = @external_group.external_identity_group_memberships.map(&:external_identity).map(&:user)
    @group_mappings = [{ group_id: @external_group.id.to_s }]
  end

  setup do
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
    EnterpriseTeam.stubs(:enabled_for_organization_security_manager?).returns(true)
  end

  test "create a new team with idp_group_id" do
    EnterpriseTeams::Helper.stubs(:idp_group_disabled?).returns(false)
    assert_difference ["EnterpriseTeam.count", "EnterpriseTeamGroupMapping.count"], 1 do
      assert_no_difference "EnterpriseTeamAssignment.count" do
        team = EnterpriseTeams::Factory.create_enterprise_team(enterprise: @enterprise, team_name: "Test Team", sync_to_organizations: "disabled", idp_group_id: @external_group.id, is_security_manager: false)
        assert_equal "Test Team", team.name
        assert_equal "disabled", team.sync_to_organizations
        assert_equal @external_group.id, T.must(team.enterprise_team_group_mappings.first).external_group_id
      end
    end
  end

  test "create a new team with security manager assignment and idp_group_id" do
    EnterpriseTeams::Helper.stubs(:idp_group_disabled?).returns(false)
    assert_difference ["EnterpriseTeam.count", "EnterpriseTeamAssignment.count", "EnterpriseTeamGroupMapping.count"], 1 do
      team = EnterpriseTeams::Factory.create_enterprise_team(enterprise: @enterprise, team_name: "Test Team", sync_to_organizations: "all", idp_group_id: @external_group.id, is_security_manager: true)
      assert_equal "Test Team", team.name
      assert_equal "all", team.sync_to_organizations
      assert_equal @external_group.id, T.must(team.enterprise_team_group_mappings.first).external_group_id
      assert team.enterprise_team_assignments.exists?(assignment_type: "security_manager")
    end
  end

  test "GHES doesn't create a new team with idp_group_id" do
    EnterpriseTeams::Helper.stubs(:idp_group_disabled?).returns(true)
    assert_no_difference ["EnterpriseTeam.count", "EnterpriseTeamGroupMapping.count"], 1 do
      assert_no_difference "EnterpriseTeamAssignment.count" do
        assert_raises_with_message(ArgumentError, "External groups for enterprise teams are not supported on GHES.") do
          team = EnterpriseTeams::Factory.create_enterprise_team(enterprise: @enterprise, team_name: "Test Team", sync_to_organizations: "disabled", idp_group_id: @external_group.id, is_security_manager: false)
          assert_nil team
        end
      end
    end
  end

  test "GHES doesn't create a new team with security manager assignment and idp_group_id" do
    EnterpriseTeams::Helper.stubs(:idp_group_disabled?).returns(true)
    assert_no_difference ["EnterpriseTeam.count", "EnterpriseTeamAssignment.count", "EnterpriseTeamGroupMapping.count"], 1 do
      assert_raises_with_message(ArgumentError, "External groups for enterprise teams are not supported on GHES.") do
        team = EnterpriseTeams::Factory.create_enterprise_team(enterprise: @enterprise, team_name: "Test Team", sync_to_organizations: "all", idp_group_id: @external_group.id, is_security_manager: true)
        assert_nil team
      end
    end
  end
end

class BusinessTeamFactoryTest < GitHub::TestCase
  setup do
    @enterprise = create :business
    @organization1 = create :organization, business: @enterprise
    @organization2 = create :organization, business: @enterprise

    BusinessTeam.stubs(:enabled_for_enterprise?).returns(true)
  end

  context "create" do
    test "create a new business team" do
      assert_difference "BusinessTeam.count", 1 do
        team = EnterpriseTeams::Factory.create_business_team(
          enterprise: @enterprise,
          team_name: "Business Team",
          description: "A new business team",
          organization_selection_type: :selected
        )
        assert_equal "Business Team", team.name
        assert_equal "A new business team", team.description
        assert_equal [], team.organization_ids
      end
    end

    test "create a new business team with all organizations" do
      assert_difference "BusinessTeam.count", 1 do
        team = EnterpriseTeams::Factory.create_business_team(
          enterprise: @enterprise,
          team_name: "Business Team",
          description: "A new business team",
          organization_selection_type: :all
        )
        assert_equal "Business Team", team.name
        assert_equal "A new business team", team.description
        assert_equal [@organization1.id, @organization2.id], team.organization_ids
      end
    end

    test "create a new business team with invalid parameters" do
      assert_no_difference "BusinessTeam.count" do
        assert_raises(ActiveRecord::RecordInvalid) do
          EnterpriseTeams::Factory.create_business_team(
            enterprise: @enterprise,
            team_name: "",
            description: "A new business team",
            organization_selection_type: :selected
          )
        end
      end
    end

    test "create a new business team with emoji in name" do
      assert_no_difference "BusinessTeam.count" do
        exception = assert_raises(ActiveRecord::RecordInvalid) do
          EnterpriseTeams::Factory.create_business_team(
            enterprise: @enterprise,
            team_name: "awesome-team 😀!",
            description: "A new business team",
            organization_selection_type: :selected
          )
        end

        assert exception.record.errors.full_messages.join(" ").include?("doesn't accept 4-byte Unicode")
      end
    end

    test "create a new business team with invalid organization_selection_type" do
      assert_no_difference "BusinessTeam.count" do
        assert_raises(ArgumentError) do
          EnterpriseTeams::Factory.create_business_team(
            enterprise: @enterprise,
            team_name: "Business Team",
            description: "A new business team",
            organization_selection_type: :invalid_type
          )
        end
      end
    end

    test "create a new business team when save fails" do
      BusinessTeam.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid.new(BusinessTeam.new))

      assert_no_difference "BusinessTeam.count" do
        assert_raises(ActiveRecord::RecordInvalid) do
          EnterpriseTeams::Factory.create_business_team(
            enterprise: @enterprise,
            team_name: "Business Team",
            description: "A new business team",
            organization_selection_type: :selected
          )
        end
      end
    end
  end

  context "update" do
    test "update an existing business team" do
      orig_team = create(:business_team, business: @enterprise, name: "Business Team", description: "A business team")

      team = EnterpriseTeams::Factory.update_business_team(
        enterprise: @enterprise,
        team_slug: orig_team.slug,
        team_name: "that team",
        description: "is updated"
      )

      orig_team.reload
      assert_equal "that team", orig_team.name
      assert_equal "is updated", orig_team.description
      assert_equal "that team", team.name
      assert_equal "is updated", team.description
      assert_equal orig_team.id, team.id
    end

    test "update a business team with invalid parameters" do
      orig_team = create(:business_team, business: @enterprise, name: "Business Team", description: "A business team")

      assert_raises(ActiveRecord::RecordInvalid) do
        EnterpriseTeams::Factory.update_business_team(
          enterprise: @enterprise,
          team_slug: orig_team.slug,
          team_name: "",
          description: "A new business team"
        )
      end
    end

    test "update a business team with emoji in name" do
      orig_team = create(:business_team, business: @enterprise, name: "Business Team", description: "A business team")

      exception = assert_raises(ActiveRecord::RecordInvalid) do
        EnterpriseTeams::Factory.update_business_team(
          enterprise: @enterprise,
          team_slug: orig_team.slug,
          team_name: "awesome-team 😀!",
          description: "A new business team"
        )
      end

      assert exception.record.errors.full_messages.join(" ").include?("doesn't accept 4-byte Unicode")
    end

    test "forwards exception when save fails" do
      orig_team = create(:business_team, business: @enterprise, name: "Business Team", description: "A business team")
      BusinessTeam.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid.new(BusinessTeam.new))

      assert_raises(ActiveRecord::RecordInvalid) do
        EnterpriseTeams::Factory.update_business_team(
          enterprise: @enterprise,
          team_slug: orig_team.slug,
          team_name: "Business Team",
          description: "A new business team"
        )
      end
    end
  end
end
