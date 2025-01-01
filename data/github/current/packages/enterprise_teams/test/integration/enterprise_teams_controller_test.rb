# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseTeamsControllerTest < GitHub::IntegrationTestCase
  include AuthenticationHelpers::SAML
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include GitHub::ReactPayloadHelper
  include GitHub::LoggerHelper

  fixtures do
    if GitHub.single_business_environment?
      setup_saml_auth_mode(with_scim: true)
      @business = create :global_business
      @provider = @business.external_provider
      @owner = @business.owners.first
    else
      @owner = create :emu, :owner
      @external_identity = @owner.external_identities.first
      @business = @owner.enterprise_managed_business
      @business.update(seats_plan_type: :basic)
    end

    @org = create(:organization, business: @business)
    @external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)
  end

  setup do
    @enterprise_team = create(:enterprise_team, business: @business)
    @mapping = EnterpriseTeamGroupMapping.create!(enterprise_team: @enterprise_team, external_group: @external_group)

    SecurityProduct::EnterpriseSecurityManagerRole.revoke!(@enterprise_team)
    if GitHub.single_business_environment?
      EnterpriseTeams::Helper.stubs(:idp_group_disabled?).returns(false)
      GitHub.stubs(:esm_enabled?).returns(true)
      setup_saml_auth_mode(with_scim: true)
      as @owner
    else
      as @owner, external_identities: @external_identity
    end
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
  end

  context "GET /enterprises/:slug/teams" do
    test "renders 404 for when disabled on GHES" do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      GitHub.stubs(:esm_enabled?).returns(false)
      get "/enterprises/#{@business.slug}/teams"
      assert_response_not_found
    end if GitHub.single_business_environment?

    test "renders 200 and renders react partial with correct props" do
      get "/enterprises/#{@business.slug}/teams"

      assert_response_success
      assert_includes response.body, "enterprise-teams-table-view"
      assert_includes response.body, {
        "props" => {
          "business_name" => @business.name,
          "business_slug" => @business.slug,
          "enterprise_teams" => [
            {
              "name" => @enterprise_team.name,
              "id" => @enterprise_team.id,
              "members" => @enterprise_team.member_count,
              "slug" => @enterprise_team.slug,
              "external_group_id" => @enterprise_team.enterprise_team_group_mappings&.first&.external_group_id,
            }
          ],
          "readonly" => false,
          "cannot_create_multiple_teams" => GitHub.esm_enabled?,
          "can_remove_teams" => !GitHub.esm_enabled?,
        }
      }.to_json
    end

    test "renders 200 with only active teams" do
      _inactive_team = create(:enterprise_team, business: @business, deleted_at: Time.now)

      get "/enterprises/#{@business.slug}/teams"

      assert_response_success
      assert_includes response.body, "enterprise-teams-table-view"
      assert_includes response.body, {
        "props" => {
          "business_name" => @business.name,
          "business_slug" => @business.slug,
          "enterprise_teams" => [
            {
              "name" => @enterprise_team.name,
              "id" => @enterprise_team.id,
              "members" => @enterprise_team.member_count,
              "slug" => @enterprise_team.slug,
              "external_group_id" => @enterprise_team.enterprise_team_group_mappings&.first&.external_group_id,
            }
          ],
          "readonly" => false,
          "cannot_create_multiple_teams" => GitHub.esm_enabled?,
          "can_remove_teams" => !GitHub.esm_enabled?,
        }
      }.to_json
    end
  end

  context "GET /enterprises/:slug/new_team" do
    test "renders 404 for when disabled on GHES" do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      GitHub.stubs(:esm_enabled?).returns(false)
      get "/enterprises/#{@business.slug}/new_team"
      assert_response_not_found
    end if GitHub.single_business_environment?

    test "redirects when trying to create more than one enterprise team in GHES" do
      get "/enterprises/#{@business.slug}/new_team"

      assert_redirected_to enterprise_teams_path(slug: @business.slug)
      follow_redirect!
      assert_equal "A maximum of one enterprise team can be created", flash[:error]
    end if GitHub.single_business_environment?

    test "renders 404 if the business doesn't exist" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

      get "/enterprises/not-a-business/new_team"

      assert_response_not_found
    end

    test "renders the correct payload and react app when enterprise_teams_enabled_for_organizations disabled" do
      if GitHub.single_business_environment?
        EnterpriseTeam.unstub(:enabled_for_organizations?)
        @enterprise_team.destroy # Only one ET can be created in GHES
      else
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)
      end

      get "/enterprises/#{@business.slug}/new_team"

      assert_response_success
      assert_template "layouts/application"
      assert_react_payload_equal(:enterprise_slug, @business.slug)
      assert_react_payload_equal(:idp_groups, [{ "id" => @external_group.id, "text" => @external_group.display_name, "member_count" => @external_group.members.count }])
      assert_react_payload_equal(:enterpriseManaged, true)
      assert_react_payload_equal(:enabledForOrganizations, GitHub.single_business_environment?)
      assert_react_payload_nil(:enterprise_team)
    end

    test "renders the correct payload and react app when enterprise_teams_enabled_for_organizations enabled" do
      @enterprise_team.destroy if GitHub.single_business_environment? # Only one ET can be created in GHES

      @business.update(seats_plan_type: :full)

      get "/enterprises/#{@business.slug}/new_team"

      assert_response_success
      assert_template "layouts/application"
      assert_react_payload_equal(:enterprise_slug, @business.slug)
      assert_react_payload_equal(:idp_groups, [{ "id" => @external_group.id, "text" => @external_group.display_name, "member_count" => @external_group.members.count }])
      assert_react_payload_equal(:enterpriseManaged, true)
      assert_react_payload_equal(:enabledForOrganizations, true)
      assert_react_payload_nil(:enterprise_team)
    end

    test "renders the correct payload and react app for non-EMU/SCIM", skip_with_all_emus: true do
      @enterprise_team.destroy if GitHub.single_business_environment? # Only one ET can be created in GHES

      owner = GitHub.single_business_environment? ? @owner : create(:user)
      business = GitHub.single_business_environment? ? @business : create(:business, owners: [owner])
      if GitHub.single_business_environment?
        @provider.destroy!
        setup_saml_auth_mode(with_scim: false)
      end

      as owner
      get "/enterprises/#{business.slug}/new_team"
      assert_response_success
      assert_template "layouts/application"
      assert_react_payload_equal(:enterprise_slug, business.slug)
      assert_react_payload_equal(:idp_groups, [])
      assert_react_payload_equal(:enterpriseManaged, false)
      assert_react_payload_nil(:enterprise_team)
    end

    test "payload blocks sync_to_organizations when business has exceeded org count" do
      GitHub.flipper[:enterprise_team_org_sync_bypass_limit].disable(@business)
      if GitHub.single_business_environment?
        @enterprise_team.destroy # Only one ET can be created in GHES
      else
        @business.update(seats_plan_type: :full)
      end
      org = create(:organization, business: @business)
      repo = create :private_repository, owner: org
      create(:repository_security_center_config, repository: repo, ghas_enabled: true)

      EnterpriseTeam.stub(:max_sync_organizations, 0) do
        get "/enterprises/#{@business.slug}/new_team"
        assert_response_success
        assert_react_payload_equal(:maxSyncOrgs, 0)
        assert_react_payload_equal(:canSyncToOrganizations, false)
      end
    end

    test "payload bypasses sync_to_organizations block when feature flagged business has exceeded org count" do
      GitHub.flipper[:enterprise_team_org_sync_bypass_limit].enable(@business)
      if GitHub.single_business_environment?
        @enterprise_team.destroy # Only one ET can be created in GHES
      else
        @business.update(seats_plan_type: :full)
      end
      org = create(:organization, business: @business)
      repo = create :private_repository, owner: org
      create(:repository_security_center_config, repository: repo, ghas_enabled: true)

      EnterpriseTeam.stub(:max_sync_organizations, 0) do
        get "/enterprises/#{@business.slug}/new_team"
        assert_response_success
        assert_react_payload_equal(:maxSyncOrgs, 0)
        assert_react_payload_equal(:canSyncToOrganizations, true)
      end
    end

    # Since we extend from BusinessController we can leverage its other existing authorization tests
    context "authorization checks" do
      test "user is not owner" do
        member = if GitHub.single_business_environment?
          create :ghes_scim_user, business: @business
        else
          create :emu, business: @business
        end
        as member, external_identities: member.external_identities.first
        get "/enterprises/#{@business.slug}/new_team"

        assert_response_not_found
      end

      test "user is not from the business" do
        rando = create :emu
        as rando, external_identities: rando.external_identities.first
        get "/enterprises/#{@business.slug}/new_team"

        assert_response_not_found
      end unless GitHub.single_business_environment?
    end
  end

  context "POST /enterprises/:slug/teams" do
    test "renders 404 for when disabled on GHES" do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      GitHub.stubs(:esm_enabled?).returns(false)
      post "/enterprises/#{@business.slug}/teams", params: {
        teamName: "TnT Team",
        idpGroup: @external_group.id.to_s,
      }
      assert_response_not_found
    end if GitHub.single_business_environment?

    test "creates a new enterprise team with the correct response" do
      @enterprise_team.destroy if GitHub.single_business_environment? # Only one ET can be created in GHES

      post "/enterprises/#{@business.slug}/teams", params: {
        teamName: "TnT Team",
        idpGroup: @external_group.id.to_s,
      }
      assert_response_success
      response_json = JSON.parse(response.body)
      assert_equal enterprise_team_members_path(slug: @business.slug, team_slug: "tnt-team"), response_json["data"]["redirect"]

      new_team = @business.enterprise_teams.find_by(name: "TnT Team")
      refute_nil new_team
      new_team = T.must(new_team)
      assert_equal "TnT Team", new_team.name
      assert_equal "tnt-team", new_team.slug

      etgm = EnterpriseTeamGroupMapping.find_by(enterprise_team_id: new_team.id)
      refute_nil etgm
      etgm = T.must(etgm)
      assert_equal @external_group.id, etgm.external_group_id
    end

    test "prevents creating more than one enterprise team in GHES" do
      post "/enterprises/#{@business.slug}/teams", params: {
        teamName: "Second Team",
        idpGroup: @external_group.id.to_s,
      }

      assert_response :forbidden
      response_json = JSON.parse(response.body)
      assert_equal "A maximum of one enterprise team can be created", response_json["data"]["error"]
    end if GitHub.single_business_environment?

    test "creates a new enterprise team with the correct sync_to_organizations when FF is enabled" do
      @enterprise_team.destroy if GitHub.single_business_environment? # Only one ET can be created in GHES

      @business.update(seats_plan_type: :full)

      post "/enterprises/#{@business.slug}/teams", params: {
        teamName: "TnT Team",
        syncToOrganizations: "true",
        isSecurityManager: "false",
      }
      assert_response_success

      new_team = @business.enterprise_teams.find_by(name: "TnT Team")
      refute_nil new_team
      new_team = T.must(new_team)
      assert_equal "all", new_team.sync_to_organizations
      refute EnterpriseTeamAssignment.find_by(enterprise_team: new_team, assignment_type: "security_manager")
      refute SecurityProduct::EnterpriseSecurityManagerRole.granted?(new_team)
    end

    test "don't create a new enterprise team with ESM when only org sync FF is enabled" do
      @business.update(seats_plan_type: :full)
      GitHub.flipper[:enterprise_teams_security_manager_sync].disable(@business)

      post "/enterprises/#{@business.slug}/teams", params: {
        teamName: "TnT Team",
        syncToOrganizations: "true",
        isSecurityManager: "true",
      }
      assert_response_success

      new_team = @business.enterprise_teams.find_by(name: "TnT Team")
      refute_nil new_team
      new_team = T.must(new_team)
      assert_equal "all", new_team.sync_to_organizations
      assert_nil EnterpriseTeamAssignment.find_by(enterprise_team: new_team, assignment_type: "security_manager")
      refute SecurityProduct::EnterpriseSecurityManagerRole.granted?(new_team)
    end unless GitHub.single_business_environment? # GHES will always have org sync + ESM

    test "creates a new enterprise team with ESM when all FFs are enabled" do
      @enterprise_team.destroy if GitHub.single_business_environment? # Only one ET can be created in GHES

      @business.update(seats_plan_type: :full)
      GitHub.flipper[:enterprise_teams_security_manager_sync].enable(@business)

      post "/enterprises/#{@business.slug}/teams", params: {
        teamName: "TnT Team",
        syncToOrganizations: "true",
        isSecurityManager: "true",
      }
      assert_response_success

      new_team = @business.enterprise_teams.find_by(name: "TnT Team")
      refute_nil new_team
      new_team = T.must(new_team)
      assert_equal "all", new_team.sync_to_organizations
      refute_nil EnterpriseTeamAssignment.find_by(enterprise_team: new_team, assignment_type: "security_manager")
      assert SecurityProduct::EnterpriseSecurityManagerRole.granted?(new_team)
    end

    test "does not create an enterprise team with ESM if sync_to_organizations is disabled" do
      @enterprise_team.destroy if GitHub.single_business_environment? # Only one ET can be created in GHES

      @business.update(seats_plan_type: :full)

      post "/enterprises/#{@business.slug}/teams", params: {
        teamName: "TnT Team",
        syncToOrganizations: "false",
        isSecurityManager: "true",
      }
      assert_response_success

      new_team = @business.enterprise_teams.find_by(name: "TnT Team")
      refute_nil new_team
      new_team = T.must(new_team)
      assert_equal "disabled", new_team.sync_to_organizations
      refute EnterpriseTeamAssignment.find_by(enterprise_team: new_team, assignment_type: "security_manager")
      refute SecurityProduct::EnterpriseSecurityManagerRole.granted?(new_team)
    end

    test "creates a new enterprise team with the default sync_to_organizations and no ESM when FF is disabled" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

      post "/enterprises/#{@business.slug}/teams", params: {
        teamName: "TnT Team",
        syncToOrganizations: "true",
        isSecurityManager: "true",
      }
      assert_response_success

      new_team = @business.enterprise_teams.find_by(name: "TnT Team")
      refute_nil new_team
      new_team = T.must(new_team)
      assert_equal "disabled", new_team.sync_to_organizations
      refute EnterpriseTeamAssignment.find_by(enterprise_team: new_team, assignment_type: "security_manager")
      refute SecurityProduct::EnterpriseSecurityManagerRole.granted?(new_team)
    end unless GitHub.single_business_environment? # GHES will always have org sync + ESM

    test "Enqueues the EnterpriseTeamOrganizationMappingJob when created with sync_to_organizations: all" do
      @enterprise_team.destroy if GitHub.single_business_environment? # Only one ET can be created in GHES

      @business.update(seats_plan_type: :full)

      assert_enqueued_with(job: EnterpriseTeamOrganizationMappingJob) do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "TnT Team",
          syncToOrganizations: "true",
        }
        assert_response_success
      end
    end

    test "Does not enqueue the EnterpriseTeamOrganizationMappingJob when created with sync_to_organizations: disabled" do
      @enterprise_team.destroy if GitHub.single_business_environment? # Only one ET can be created in GHES

      assert_no_enqueued_jobs(only: EnterpriseTeamOrganizationMappingJob) do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "TnT Team",
          syncToOrganizations: "false",
        }
        assert_response_success
      end
    end

    test "Does not enqueue the EnterpriseTeamOrganizationMappingJob when created with sync_to_organizations: all when ff is disabled" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

      assert_no_enqueued_jobs(only: EnterpriseTeamOrganizationMappingJob) do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "TnT Team",
          syncToOrganizations: "true",
        }
        assert_response_success
      end
    end unless GitHub.single_business_environment? # GHES will always have org sync + ESM

    test "Enqueues the EnterpriseTeamOrganizationMappingJob when updated with sync_to_organizations: all" do
      @business.update(seats_plan_type: :full)

      assert_enqueued_with(job: EnterpriseTeamOrganizationMappingJob) do
        patch "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
          teamName: "Updated Team",
          syncToOrganizations: "true",
        }
        assert_response_success
      end
    end

    test "Does enqueue the EnterpriseTeamOrganizationMappingJob when updated with sync_to_organizations: disabled" do
      assert_enqueued_with(job: EnterpriseTeamOrganizationMappingJob) do
        patch "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
          teamName: "Updated Team",
          syncToOrganizations: "false",
        }
        assert_response_success
      end
    end

    test "Does not enqueue the EnterpriseTeamOrganizationMappingJob when updated with sync_to_organizations: all when ff is disabled" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

      assert_no_enqueued_jobs(only: EnterpriseTeamOrganizationMappingJob) do
        patch "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
          teamName: "Updated Team",
          syncToOrganizations: "true",
        }
        assert_response_success
      end
    end unless GitHub.single_business_environment? # GHES will always have org sync + ESM

    test "allows usage of duplicate name across enterprises" do
      owner = create :emu, :owner
      external_identity = owner.external_identities.first
      business = owner.enterprise_managed_business
      business.update(seats_plan_type: :basic)
      enterprise_team = create(:enterprise_team, business: business, name: "A Truly Unique Name")
      as owner, external_identities: external_identity
      post "/enterprises/#{business.slug}/teams", params: {
        teamName: @enterprise_team.name,
      }
      assert_response_success

      new_team = @business.enterprise_teams.find_by(name: @enterprise_team.name)
      refute_nil new_team
    end unless GitHub.single_business_environment?

    context "quality checks" do
      test "does not allow usage of a non integer idpGroup param" do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "TnT Team",
          idpGroup: "two",
        }
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Invalid external group selection.", response_json["data"]["error"]
      end

      test "does not allow usage of a destroyed external group" do
        ghost_external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)
        ghost_external_group.deleted_at = Time.now
        ghost_external_group.save!

        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "TnT Team",
          idpGroup: ghost_external_group.id.to_s,
        }
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Invalid external group selection.", response_json["data"]["error"]
      end

      test "does not allow usage of another business's external group" do
        # Generates another EMU with its own external group
        external_owner = create :emu, :owner
        external_external_identity = external_owner.external_identities.first
        external_business = external_owner.enterprise_managed_business
        external_business.update(seats_plan_type: :basic)
        external_external_group = create(:external_group, :with_members, :with_team, business: external_business, number_of_members: 2)

        as @owner, external_identities: @external_identity
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "TnT Team",
          idpGroup: external_external_group.id.to_s,
        }
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Invalid external group selection.", response_json["data"]["error"]
      end unless GitHub.single_business_environment?

      test "blocks usage of empty team name" do
        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: "",
        }
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name cannot be empty.", response_json["data"]["error"]
      end

      test "requires teamName parameter" do
        post "/enterprises/#{@business.slug}/teams", params: {}
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name cannot be empty.", response_json["data"]["error"]
      end

      test "blocks usage of existing active team name" do
        enterprise_team = create(:enterprise_team, business: @business)

        post "/enterprises/#{@business.slug}/teams", params: {
          teamName: enterprise_team.name,
        }

        assert_response :bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name must be unique for this business", response_json["data"]["error"]
      end unless GitHub.single_business_environment? # Only one ET can be created in GHES, so we can't create another with the same name
    end

    context "logging and metrics" do
      test "on successful creation" do
        @enterprise_team.destroy if GitHub.single_business_environment? # Only one ET can be created in GHES

        logs = capture_logs do
          post "/enterprises/#{@business.slug}/teams", params: {
            teamName: "TnT Team",
            idpGroup: @external_group.id.to_s,
          }
          assert_response_success
        end
        new_team = T.must(@business.enterprise_teams.find_by(name: "TnT Team"))
        new_etgm = T.must(EnterpriseTeamGroupMapping.find_by(enterprise_team_id: new_team.id))

        assert_log_match(logs, "Body", "Successfully created enterprise team.")
        assert_log_match(logs, "code.namespace", "EnterpriseTeamsController")
        assert_log_match(logs, "code.function", "create_enterprise_team")
        assert_log_match(logs, "gh.actor.id", @owner.id)
        assert_log_match(logs, "gh.business.id", @business.id)
        assert_log_match(logs, "gh.external_group_id", @external_group.id)
        assert_log_match(logs, "gh.enterprise_team.id", new_team.id)
        assert_log_match(logs, "gh.enterprise_team.group_mapping.id", new_etgm.id)
      end
    end
  end

  context "GET /enterprises/:slug/teams/:team_slug/edit" do
    test "renders 404 for when disabled on GHES" do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      GitHub.stubs(:esm_enabled?).returns(false)
      get "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}/edit"
      assert_response_not_found
    end if GitHub.single_business_environment?

    test "renders the correct payload and react app" do
      if GitHub.single_business_environment?
        EnterpriseTeam.unstub(:enabled_for_organizations?)
      else
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)
      end

      get "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}/edit"

      assert_response_success
      assert_template "layouts/application"
      assert_react_payload_equal(:enterprise_slug, @business.slug)
      assert_react_payload_equal(:idp_groups, [{
        "id" => @external_group.id,
        "text" => @external_group.display_name,
        "member_count" => @external_group.members.count
      }])
      assert_react_payload_equal(:enterpriseManaged, true)
      assert_react_payload_equal(:enabledForOrganizations, GitHub.single_business_environment?)  # GHES will always have org sync
      assert_react_payload_equal(:enabledForOrganizationSecurityManager, GitHub.single_business_environment?) # ^ same for ESM
      if GitHub.single_business_environment?
        assert_react_payload_equal(:enterprise_team, {
            "name" => @enterprise_team.name,
            "slug" => @enterprise_team.slug,
            "idpGroup" => {
              "id" => @external_group.id,
              "text" => @external_group.display_name
            },
            # The following params show up for GHES since the features are togglable
            "syncToOrganizations" => false,
            "isSecurityManager" => false
          }
        )
      else
        assert_react_payload_equal(:enterprise_team, {
            "name" => @enterprise_team.name,
            "slug" => @enterprise_team.slug,
            "idpGroup" => {
              "id" => @external_group.id,
              "text" => @external_group.display_name
            },
          }
        )
      end
    end

    test "renders the correct payload and react app when just enterprise_teams_enabled_for_organizations is enabled" do
      @business.update(seats_plan_type: :full)
      GitHub.flipper[:enterprise_teams_security_manager_sync].disable(@business)

      get "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}/edit"

      assert_response_success
      assert_template "layouts/application"
      assert_react_payload_equal(:enterprise_slug, @business.slug)
      assert_react_payload_equal(:idp_groups, [{
        "id" => @external_group.id,
        "text" => @external_group.display_name,
        "member_count" => @external_group.members.count
      }])
      assert_react_payload_equal(:enterpriseManaged, true)
      assert_react_payload_equal(:enabledForOrganizations, true)
      assert_react_payload_equal(:enabledForOrganizationSecurityManager, false)
      assert_react_payload_equal(:enterprise_team, {
          "name" => @enterprise_team.name,
          "slug" => @enterprise_team.slug,
          "idpGroup" => {
            "id" => @external_group.id,
            "text" => @external_group.display_name
          },
          "syncToOrganizations" => false
        }
      )
    end unless GitHub.single_business_environment? # GHES will always have org sync + ESM

    test "renders the correct payload and react app when security manager sync enabled" do
      @business.update(seats_plan_type: :full)
      GitHub.flipper[:enterprise_teams_security_manager_sync].enable(@business)

      get "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}/edit"

      assert_response_success
      assert_template "layouts/application"
      assert_react_payload_equal(:enterprise_slug, @business.slug)
      assert_react_payload_equal(:idp_groups, [{
        "id" => @external_group.id,
        "text" => @external_group.display_name,
        "member_count" => @external_group.members.count
      }])
      assert_react_payload_equal(:enterpriseManaged, true)
      assert_react_payload_equal(:enabledForOrganizations, true)
      assert_react_payload_equal(:enabledForOrganizationSecurityManager, true)
      assert_react_payload_equal(:enterprise_team, {
          "name" => @enterprise_team.name,
          "slug" => @enterprise_team.slug,
          "idpGroup" => {
            "id" => @external_group.id,
            "text" => @external_group.display_name
          },
          "syncToOrganizations" => false,
          "isSecurityManager" => false,
        }
      )
    end

    test "renders the correct payload and react app for non-EMU/SCIM", skip_with_all_emus: true do
      owner = GitHub.single_business_environment? ? @owner : create(:user)
      business = GitHub.single_business_environment? ? @business : create(:business, owners: [owner])
      if GitHub.single_business_environment?
        @provider.destroy!
        setup_saml_auth_mode(with_scim: false)
      else
        GitHub.flipper[:enterprise_teams_security_manager_sync].disable(business)
      end
      enterprise_team = create(:enterprise_team, business: business)

      as owner
      get "/enterprises/#{business.slug}/teams/#{enterprise_team.slug}/edit"
      assert_response_success
      assert_template "layouts/application"
      assert_react_payload_equal(:enterprise_slug, business.slug)
      assert_react_payload_equal(:idp_groups, [])
      assert_react_payload_equal(:enterpriseManaged, false)
      assert_react_payload_equal(:enabledForOrganizations, true)
      if GitHub.single_business_environment?
        assert_react_payload_equal(:enterprise_team, {
            "name" => enterprise_team.name,
            "slug" => enterprise_team.slug,
            "syncToOrganizations" => false,
            "isSecurityManager" => false, # GHES always has ESM with org sync
          }
        )
      else
        assert_react_payload_equal(:enterprise_team, {
            "name" => enterprise_team.name,
            "slug" => enterprise_team.slug,
            "syncToOrganizations" => false,
          }
        )
      end
    end

    test "payload blocks sync_to_organizations when business has exceeded org count" do
      @business.update(seats_plan_type: :full)
      GitHub.flipper[:enterprise_team_org_sync_bypass_limit].disable(@business)
      org = create(:organization, business: @business)
      repo = create :private_repository, owner: org
      create(:repository_security_center_config, repository: repo, ghas_enabled: true)

      EnterpriseTeam.stub(:max_sync_organizations, 0) do
        get "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}/edit"
        assert_response_success
        assert_react_payload_equal(:maxSyncOrgs, 0)
        assert_react_payload_equal(:canSyncToOrganizations, false)
      end
    end

    test "payload allows sync_to_organizations to stay enabled if already enabled when business has exceeded org count" do
      @business.update(seats_plan_type: :full)
      GitHub.flipper[:enterprise_team_org_sync_bypass_limit].disable(@business)
      org = create(:organization, business: @business)
      repo = create :private_repository, owner: org
      create(:repository_security_center_config, repository: repo, ghas_enabled: true)

      @enterprise_team.sync_to_organizations = "all"
      @enterprise_team.save!

      EnterpriseTeam.stub(:max_sync_organizations, 0) do
        get "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}/edit"
        assert_response_success
        assert_react_payload_equal(:maxSyncOrgs, 0)
        assert_react_payload_equal(:canSyncToOrganizations, true)
      end
    end

    test "payload bypasses sync_to_organizations check when feature flagged business has exceeded org count" do
      GitHub.flipper[:enterprise_team_org_sync_bypass_limit].enable(@business)
      @business.update(seats_plan_type: :full) unless GitHub.single_business_environment?
      org = create(:organization, business: @business)
      repo = create :private_repository, owner: org
      create(:repository_security_center_config, repository: repo, ghas_enabled: true)

      EnterpriseTeam.stub(:max_sync_organizations, 0) do
        get "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}/edit"
        assert_response_success
        assert_react_payload_equal(:maxSyncOrgs, 0)
        assert_react_payload_equal(:canSyncToOrganizations, true)
      end
    end

    context "authorization checks" do
      test "user is not owner" do
        member = if GitHub.single_business_environment?
          create :ghes_scim_user, business: @business
        else
          create :emu, business: @business
        end
        as member, external_identities: member.external_identities.first
        get "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}/edit"

        assert_response_not_found
      end

      test "user is not from the business" do
        rando = create :emu
        as rando, external_identities: rando.external_identities.first
        get "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}/edit"

        assert_response_not_found
      end unless GitHub.single_business_environment?
    end
  end

  context "PUT /enterprises/:slug/teams/:team_slug" do
    test "renders 404 for when disabled on GHES" do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      GitHub.stubs(:esm_enabled?).returns(false)
      new_external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)
      put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
        teamName: "TnT Team",
        idpGroup: new_external_group.id.to_s,
      }
      assert_response_not_found
    end if GitHub.single_business_environment?

    test "correctly updates the enterprise team from direct members to IDP" do
      @enterprise_team.enterprise_team_memberships.create!(user: @owner)
      assert_equal 1, @enterprise_team.enterprise_team_memberships.count

      new_external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)

      perform_enqueued_jobs(only: [ClearEnterpriseTeamMembershipsJob]) do
        put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
          teamName: "TnT Team",
          idpGroup: new_external_group.id.to_s,
        }
      end

      assert_response_success
      response_json = JSON.parse(response.body)
      assert_equal enterprise_team_members_path(slug: @business.slug, team_slug: "tnt-team"), response_json["data"]["redirect"]

      updated_team = @business.enterprise_teams.find_by(name: "TnT Team")
      refute_nil updated_team
      updated_team = T.must(updated_team)
      assert_equal "TnT Team", updated_team.name
      assert_equal "tnt-team", updated_team.slug

      etgm = EnterpriseTeamGroupMapping.find_by(enterprise_team_id: updated_team.id)
      refute_nil etgm
      etgm = T.must(etgm)
      assert_equal new_external_group.id, etgm.external_group_id
      assert_nil etgm.deleted_at

      assert_equal 0, @enterprise_team.enterprise_team_memberships.count
    end

    test "correctly soft deletes the etgm" do
      put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
        teamName: @enterprise_team.name,
      }
      assert_response_success
      response_json = JSON.parse(response.body)
      assert_equal enterprise_team_members_path(slug: @business.slug, team_slug: @enterprise_team.slug), response_json["data"]["redirect"]

      updated_team = @business.enterprise_teams.find_by(name: @enterprise_team.name)
      refute_nil updated_team
      updated_team = T.must(updated_team)
      assert_equal @enterprise_team.name, updated_team.name
      assert_equal @enterprise_team.slug, updated_team.slug

      etgm = EnterpriseTeamGroupMapping.find_by(enterprise_team_id: updated_team.id)
      refute_nil etgm
      etgm = T.must(etgm)
      refute_nil etgm.deleted_at
    end

    test "allows usage of duplicate name across enterprises" do
      owner = create :emu, :owner
      external_identity = owner.external_identities.first
      business = owner.enterprise_managed_business
      business.update(seats_plan_type: :basic)
      enterprise_team = create(:enterprise_team, business: business, name: "A Truly Unique Name")
      as owner, external_identities: external_identity
      put "/enterprises/#{business.slug}/teams/#{enterprise_team.slug}", params: {
        teamName: @enterprise_team.name,
      }
      assert_response_success

      new_team = @business.enterprise_teams.find_by(name: @enterprise_team.name)
      refute_nil new_team
    end unless GitHub.single_business_environment?

    test "correctly updates sync_to_organizations when FF is enabled" do
      @business.update(seats_plan_type: :full)

      put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
        teamName: "TnT Team",
        idpGroup: @external_group.id.to_s,
        syncToOrganizations: "true",
        isSecurityManager: "false"
      }

      assert_response_success
      assert_equal "all", @enterprise_team.reload.sync_to_organizations
      refute EnterpriseTeamAssignment.find_by(enterprise_team: @enterprise_team, assignment_type: "security_manager")
    end

    test "don't update ESM when only org sync is enabled" do
      @business.update(seats_plan_type: :full)
      GitHub.flipper[:enterprise_teams_security_manager_sync].disable(@business)

      put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
        teamName: "TnT Team",
        idpGroup: @external_group.id.to_s,
        syncToOrganizations: "true",
        isSecurityManager: "true"
      }

      assert_response_success
      assert_equal "all", @enterprise_team.reload.sync_to_organizations
      assert_nil EnterpriseTeamAssignment.find_by(enterprise_team: @enterprise_team, assignment_type: "security_manager")
      refute SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)
    end unless GitHub.single_business_environment? # GHES will always have org sync + ESM

    test "correctly updates ESM when FFs are enabled" do
      @business.update(seats_plan_type: :full)
      GitHub.flipper[:enterprise_teams_security_manager_sync].enable(@business)

      put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
        teamName: "TnT Team",
        idpGroup: @external_group.id.to_s,
        syncToOrganizations: "true",
        isSecurityManager: "true"
      }

      assert_response_success
      assert_equal "all", @enterprise_team.reload.sync_to_organizations
      refute_nil EnterpriseTeamAssignment.find_by(enterprise_team: @enterprise_team, assignment_type: "security_manager")
      assert SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)
    end

    test "creates an ESM when FF is enabled and team has an existing assignment" do
      @business.update(seats_plan_type: :full)
      GitHub.flipper[:enterprise_teams_security_manager_sync].enable(@business)
      EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: :copilot)
      SecurityProduct::EnterpriseSecurityManagerRole.grant!(@enterprise_team)

      put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
        teamName: "TnT Team",
        idpGroup: @external_group.id.to_s,
        syncToOrganizations: "true",
        isSecurityManager: "true"
      }

      assert_response_success
      assert_equal "all", @enterprise_team.reload.sync_to_organizations
      refute_nil EnterpriseTeamAssignment.find_by(enterprise_team: @enterprise_team, assignment_type: "security_manager")
      assert EnterpriseTeamAssignment.find_by(enterprise_team: @enterprise_team, assignment_type: :copilot)
      assert SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)
    end

    test "does not update ESM when sync_to_organizations is disabled" do
      @business.update(seats_plan_type: :full)

      put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
        teamName: "TnT Team",
        idpGroup: @external_group.id.to_s,
        syncToOrganizations: "false",
        isSecurityManager: "true"
      }

      assert_response_success
      assert_equal "disabled", @enterprise_team.reload.sync_to_organizations
      refute EnterpriseTeamAssignment.find_by(enterprise_team: @enterprise_team, assignment_type: "security_manager")
      refute SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)
    end

    test "destroys ESM assignment when FF is enabled" do
      @business.update(seats_plan_type: :full)
      GitHub.flipper[:enterprise_teams_security_manager_sync].enable(@business)
      @enterprise_team.sync_to_organizations = "all"
      @enterprise_team.save!
      eta = EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: "security_manager")
      SecurityProduct::EnterpriseSecurityManagerRole.grant!(@enterprise_team)

      put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
        teamName: "TnT Team",
        idpGroup: @external_group.id.to_s,
        syncToOrganizations: "true",
        isSecurityManager: "false"
      }

      assert_response_success
      refute EnterpriseTeamAssignment.find_by(id: eta.id)
      refute SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)
    end

    test "Don't destroy ESM assignment when security_manager_sync is disabled" do
      @business.update(seats_plan_type: :full)
      GitHub.flipper[:enterprise_teams_security_manager_sync].disable(@business)
      @enterprise_team.sync_to_organizations = "all"
      @enterprise_team.save!
      eta = EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: "security_manager")
      SecurityProduct::EnterpriseSecurityManagerRole.grant!(@enterprise_team)

      put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
        teamName: "TnT Team",
        idpGroup: @external_group.id.to_s,
        syncToOrganizations: "false",
      }

      assert_response_success
      assert EnterpriseTeamAssignment.find_by(id: eta.id)
      assert SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)
    end unless GitHub.single_business_environment? # GHES will always have both org sync and ESM

    test "destroys ESM assignment when sync_to_organizations is disabled" do
      @business.update(seats_plan_type: :full)
      GitHub.flipper[:enterprise_teams_security_manager_sync].enable(@business)
      @enterprise_team.sync_to_organizations = "all"
      @enterprise_team.save!
      eta = EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: "security_manager")
      SecurityProduct::EnterpriseSecurityManagerRole.grant!(@enterprise_team)

      put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
        teamName: "TnT Team",
        idpGroup: @external_group.id.to_s,
        syncToOrganizations: "false",
      }

      assert_response_success
      refute EnterpriseTeamAssignment.find_by(id: eta.id)
      refute SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)
    end

    context "clearing organization team mappings" do
      test "Do not enqueue the EnterpriseTeamOrganizationMappingJob when updated with sync_to_organizations: disabled if FF disabled" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

        assert_no_enqueued_jobs(only: EnterpriseTeamOrganizationMappingJob) do
          put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
            teamName: "TnT Team",
            syncToOrganizations: "false",
          }
          assert_response_success
        end
      end unless GitHub.single_business_environment? # GHES will always have org sync

      test "Do not enqueue the EnterpriseTeamOrganizationMappingJob when updated with sync_to_organizations: all if FF disabled" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

        assert_no_enqueued_jobs(only: EnterpriseTeamOrganizationMappingJob) do
          put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
            teamName: "TnT Team",
            syncToOrganizations: "true",
          }
          assert_response_success
        end
      end unless GitHub.single_business_environment? # GHES will always have org sync

      test "Enqueues the EnterpriseTeamOrganizationMappingJob when updated with sync_to_organizations: disabled" do
        @business.update(seats_plan_type: :full)

        assert_enqueued_with(job: EnterpriseTeamOrganizationMappingJob) do
          put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
            teamName: "TnT Team",
            syncToOrganizations: "false",
          }
          assert_response_success
        end
      end
    end

    context "quality checks" do
      test "does not allow usage of a non integer idpGroup param" do
        put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
          teamName: "TnT Team",
          idpGroup: "two",
        }
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Invalid external group selection.", response_json["data"]["error"]
      end

      test "does not allow usage of a destroyed external group" do
        ghost_external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)
        ghost_external_group.deleted_at = Time.now
        ghost_external_group.save!

        put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
          teamName: "TnT Team",
          idpGroup: ghost_external_group.id.to_s,
        }
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Invalid external group selection.", response_json["data"]["error"]
      end

      test "does not allow usage of another business's external group" do
        # Generates another EMU with its own external group
        external_owner = create :emu, :owner
        external_external_identity = external_owner.external_identities.first
        external_business = external_owner.enterprise_managed_business
        external_business.update(seats_plan_type: :basic)
        external_external_group = create(:external_group, :with_members, :with_team, business: external_business, number_of_members: 2)

        as @owner, external_identities: @external_identity
        put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
          teamName: "TnT Team",
          idpGroup: external_external_group.id.to_s,
        }
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Invalid external group selection.", response_json["data"]["error"]
      end unless GitHub.single_business_environment?

      test "blocks usage of empty team name" do
        put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
          teamName: "",
        }
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name cannot be empty.", response_json["data"]["error"]
      end

      test "requires teamName parameter" do
        put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {}
        assert_response_bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name cannot be empty.", response_json["data"]["error"]
      end

      test "blocks usage of existing active team name" do
        enterprise_team = create(:enterprise_team, business: @business)

        put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
          teamName: enterprise_team.name,
        }

        assert_response :bad_request
        response_json = JSON.parse(response.body)
        assert_equal "Name must be unique for this business", response_json["data"]["error"]
      end
    end

    context "logging and metrics" do
      test "on successful update" do
        new_external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)
        logs = capture_logs do
          put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
            teamName: "TnT Team",
            idpGroup: new_external_group.id.to_s,
          }
          assert_response_success
        end
        new_team = T.must(@business.enterprise_teams.find_by(name: "TnT Team"))
        new_etgm = T.must(EnterpriseTeamGroupMapping.find_by(enterprise_team_id: new_team.id))

        assert_log_match(logs, "Body", "Successfully updated enterprise team.")
        assert_log_match(logs, "code.namespace", "EnterpriseTeamsController")
        assert_log_match(logs, "code.function", "update_enterprise_team")
        assert_log_match(logs, "gh.actor.id", @owner.id)
        assert_log_match(logs, "gh.business.id", @business.id)
        assert_log_match(logs, "gh.external_group.id", new_external_group.id)
        assert_log_match(logs, "gh.enterprise_team.id", new_team.id)
        assert_log_match(logs, "gh.enterprise_team.group_mapping.id", new_etgm.id)
      end
    end
  end

  context "DELETE /enterprises/:slug/teams/:team_slug" do
    test "renders 404 for when disabled on GHES", enterprise_only: true do
      EnterpriseTeam.unstub(:enabled_for_organizations?)
      GitHub.stubs(:esm_enabled?).returns(false)
      delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [@enterprise_team.slug] }
      assert_response_not_found
    end

    test "renders 404 as delete is disabled in GHES", enterprise_only: true do
      delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [@enterprise_team.slug] }
      assert_response_not_found
    end

    # TODO remove skip_enterprise: true when we allow deleting teams in GHES
    test "deletes the team matching the slug when enabled_for_organizations? is false", skip_enterprise: true do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)
      Business.any_instance.stubs(:enterprise_teams_enabled?).returns(true)

      delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [@enterprise_team.slug] }

      assert_response_success
      response_json = JSON.parse(response.body)
      assert_equal enterprise_teams_url(slug: @business.slug), response_json["data"]["redirect"]
      refute EnterpriseTeam.exists?(@enterprise_team.id)
    end

    # TODO remove skip_enterprise: true when we allow deleting teams in GHES
    test "deletes multiple teams matching the slug when enabled_for_organizations? is false", skip_enterprise: true do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)
      Business.any_instance.stubs(:enterprise_teams_enabled?).returns(true)

      enterprise_team2 = create(:enterprise_team, business: @business)

      delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: {
        team_slugs: [@enterprise_team.slug, enterprise_team2.slug]
      }

      assert_response_success
      response_json = JSON.parse(response.body)
      assert_equal enterprise_teams_url(slug: @business.slug), response_json["data"]["redirect"]
      refute EnterpriseTeam.exists?(@enterprise_team.id)
      refute EnterpriseTeam.exists?(enterprise_team2.id)
    end

    # TODO remove skip_enterprise: true when we allow deleting teams in GHES
    test "deletes the team matching the slug when enabled_for_organizations? is true but no mappings exist", skip_enterprise: true do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      perform_enqueued_jobs(only: [EnterpriseTeamOrganizationMappingJob, EnterpriseTeamOrganizationReconciliationJob, EnterpriseTeamOrganizationReconciliationRunnerJob]) do
        delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [@enterprise_team.slug] }
      end

      assert_response_success
      response_json = JSON.parse(response.body)
      assert_equal enterprise_teams_url(slug: @business.slug), response_json["data"]["redirect"]
      refute EnterpriseTeam.exists?(@enterprise_team.id)
    end

    # TODO remove skip_enterprise: true when we allow deleting teams in GHES
    test "soft deletes the team matching before enqueuing jobs", skip_enterprise: true do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      org_team = create(:team, organization: @org)
      mapping = EnterpriseTeamOrganizationMapping.create(enterprise_team: @enterprise_team, organization: @org, team: org_team)

      EnterpriseTeamOrganizationMappingJob.expects(:perform_later).with do
        assert(EnterpriseTeam.unscoped.find_by(id: @enterprise_team.id).soft_deleted?)
      end
      delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [@enterprise_team.slug] }

      assert_response_success
      response_json = JSON.parse(response.body)
      assert_equal enterprise_teams_url(slug: @business.slug), response_json["data"]["redirect"]
    end

    # TODO remove skip_enterprise: true when we allow deleting teams in GHES
    test "deletes the team matching the slug and cleans up mappings", skip_enterprise: true do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      org_team = create(:team, organization: @org)
      mapping = EnterpriseTeamOrganizationMapping.create(enterprise_team: @enterprise_team, organization: @org, team: org_team)

      perform_enqueued_jobs(only: [EnterpriseTeamOrganizationMappingJob, EnterpriseTeamOrganizationReconciliationJob, EnterpriseTeamOrganizationReconciliationRunnerJob]) do
        delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [@enterprise_team.slug] }
      end

      assert_response_success
      response_json = JSON.parse(response.body)
      assert_equal enterprise_teams_url(slug: @business.slug), response_json["data"]["redirect"]
      refute EnterpriseTeam.exists?(@enterprise_team.id)
      refute EnterpriseTeamOrganizationMapping.exists?(mapping.id)
      refute Team.exists?(org_team.id)
    end

    # TODO remove skip_enterprise: true when we allow deleting teams in GHES
    test "deletes multiple teams matching the slug and cleans up mappings", skip_enterprise: true do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      org_team = create(:team, organization: @org)
      mapping = EnterpriseTeamOrganizationMapping.create(enterprise_team: @enterprise_team, organization: @org, team: org_team)

      enterprise_team2 = create(:enterprise_team, business: @business)
      org_team2 = create(:team, organization: @org)
      mapping2 = EnterpriseTeamOrganizationMapping.create(enterprise_team: enterprise_team2, organization: @org, team: org_team2)

      perform_enqueued_jobs(only: [EnterpriseTeamOrganizationMappingJob, EnterpriseTeamOrganizationReconciliationJob, EnterpriseTeamOrganizationReconciliationRunnerJob]) do
        delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: {
          team_slugs: [@enterprise_team.slug, enterprise_team2.slug]
        }
      end

      assert_response_success
      response_json = JSON.parse(response.body)
      assert_equal enterprise_teams_url(slug: @business.slug), response_json["data"]["redirect"]
      refute EnterpriseTeam.exists?(@enterprise_team.id)
      refute EnterpriseTeam.exists?(enterprise_team2.id)
      refute EnterpriseTeamOrganizationMapping.exists?(mapping.id)
      refute EnterpriseTeamOrganizationMapping.exists?(mapping2.id)
      refute Team.exists?(org_team.id)
      refute Team.exists?(org_team2.id)
    end

    # TODO remove skip_enterprise: true when we allow deleting teams in GHES
    test "returns error when no team is found with the slug", skip_enterprise: true do
      delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: ["something else"] }

      assert_response_not_found
      response_json = JSON.parse(response.body)
      assert_equal "No team found.", response_json["data"]["error"]
    end

    # TODO remove skip_enterprise: true when we allow deleting teams in GHES
    test "returns error when no slugs are passed in", skip_enterprise: true do
      delete "/enterprises/#{@business.slug}/teams/bulk_delete", params: { team_slugs: [] }

      assert_response_not_found
      response_json = JSON.parse(response.body)
      assert_equal "No team found.", response_json["data"]["error"]
    end
  end
end

# We are disabling idp groups for enterprise teams in GHES. These tests are copied from above and modified
# to reflect the idp disablement. The class can be wholly removed as well as the EnterpriseTeams::Helper.stubs(:idp_group_disabled?).returns(false)
# line in the above tests when the GHES functionality returns.
class EnterpriseTeamsControllerGHESTests < GitHub::IntegrationTestCase
  include AuthenticationHelpers::SAML
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include GitHub::ReactPayloadHelper
  include GitHub::LoggerHelper

  fixtures do
    skip unless GitHub.enterprise?
    setup_saml_auth_mode(with_scim: true)
    @business = create :global_business
    @provider = @business.external_provider
    @owner = @business.owners.first

    @org = create(:organization, business: @business)
    @external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)
  end

  setup do
    @enterprise_team = create(:enterprise_team, business: @business)
    @mapping = EnterpriseTeamGroupMapping.create!(enterprise_team: @enterprise_team, external_group: @external_group)
    SecurityProduct::EnterpriseSecurityManagerRole.revoke!(@enterprise_team)
    EnterpriseTeams::Helper.stubs(:idp_group_disabled?).returns(true)
    GitHub.stubs(:esm_enabled?).returns(true)
    setup_saml_auth_mode(with_scim: true)
    as @owner
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
  end

  test "correctly doesn't update sync_to_organizations when FF is enabled" do
    @business.update(seats_plan_type: :full)

    put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
      teamName: "TnT Team",
      idpGroup: @external_group.id.to_s,
      syncToOrganizations: "true",
      isSecurityManager: "false"
    }

    assert_response_bad_request
    response_json = JSON.parse(response.body)
    assert_equal "External groups for enterprise teams are not supported on GHES.", response_json["data"]["error"]
    refute EnterpriseTeamAssignment.find_by(enterprise_team: @enterprise_team, assignment_type: "security_manager")
  end

  test "doesn't creates a new enterprise team with the correct response" do
    post "/enterprises/#{@business.slug}/teams", params: {
      teamName: "TnT Team",
      idpGroup: @external_group.id.to_s,
    }
    assert_response_bad_request
    response_json = JSON.parse(response.body)
    assert_equal "External groups for enterprise teams are not supported on GHES.", response_json["data"]["error"]

    new_team = @business.enterprise_teams.find_by(name: "TnT Team")
    assert_nil new_team
  end

  test "correctly doesn't update ESM when FFs are enabled" do
    @business.update(seats_plan_type: :full)
    GitHub.flipper[:enterprise_teams_security_manager_sync].enable(@business)

    put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
      teamName: "TnT Team",
      idpGroup: @external_group.id.to_s,
      syncToOrganizations: "true",
      isSecurityManager: "true"
    }

    assert_response_bad_request
    response_json = JSON.parse(response.body)
    assert_equal "External groups for enterprise teams are not supported on GHES.", response_json["data"]["error"]

    assert_nil EnterpriseTeamAssignment.find_by(enterprise_team: @enterprise_team, assignment_type: "security_manager")
    refute SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)
  end

  test "correctly doesn't update the enterprise team from direct members to IDP" do
    @enterprise_team.enterprise_team_memberships.create!(user: @owner)
    assert_equal 1, @enterprise_team.enterprise_team_memberships.count

    new_external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)

    perform_enqueued_jobs(only: [ClearEnterpriseTeamMembershipsJob]) do
      put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
        teamName: "TnT Team",
        idpGroup: new_external_group.id.to_s,
      }
    end

    assert_response_bad_request
    response_json = JSON.parse(response.body)
    assert_equal "External groups for enterprise teams are not supported on GHES.", response_json["data"]["error"]

    assert_equal 1, @enterprise_team.enterprise_team_memberships.count
  end

  test "creates an ESM when FF is enabled and team has an existing assignment" do
    @business.update(seats_plan_type: :full)
    GitHub.flipper[:enterprise_teams_security_manager_sync].enable(@business)
    EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: :copilot)
    SecurityProduct::EnterpriseSecurityManagerRole.grant!(@enterprise_team)

    put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
      teamName: "TnT Team",
      idpGroup: @external_group.id.to_s,
      syncToOrganizations: "true",
      isSecurityManager: "true"
    }

    assert_response_bad_request
    response_json = JSON.parse(response.body)
    assert_equal "External groups for enterprise teams are not supported on GHES.", response_json["data"]["error"]

    assert_equal "disabled", @enterprise_team.reload.sync_to_organizations
    assert_nil EnterpriseTeamAssignment.find_by(enterprise_team: @enterprise_team, assignment_type: "security_manager")
    assert EnterpriseTeamAssignment.find_by(enterprise_team: @enterprise_team, assignment_type: :copilot)
    assert SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)
  end

  test "doesn't destroy ESM assignment when FF is enabled" do
    @business.update(seats_plan_type: :full)
    GitHub.flipper[:enterprise_teams_security_manager_sync].enable(@business)
    @enterprise_team.sync_to_organizations = "all"
    @enterprise_team.save!
    eta = EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: "security_manager")
    SecurityProduct::EnterpriseSecurityManagerRole.grant!(@enterprise_team)

    put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
      teamName: "TnT Team",
      idpGroup: @external_group.id.to_s,
      syncToOrganizations: "true",
      isSecurityManager: "false"
    }

    assert_response_bad_request
    response_json = JSON.parse(response.body)
    assert_equal "External groups for enterprise teams are not supported on GHES.", response_json["data"]["error"]
    assert EnterpriseTeamAssignment.find_by(id: eta.id)
    assert SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)
  end

  test "does not update ESM when sync_to_organizations is disabled" do
    @business.update(seats_plan_type: :full)

    put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
      teamName: "TnT Team",
      idpGroup: @external_group.id.to_s,
      syncToOrganizations: "false",
      isSecurityManager: "true"
    }

    assert_response_bad_request
    response_json = JSON.parse(response.body)
    assert_equal "External groups for enterprise teams are not supported on GHES.", response_json["data"]["error"]
    assert_equal "disabled", @enterprise_team.reload.sync_to_organizations
    refute EnterpriseTeamAssignment.find_by(enterprise_team: @enterprise_team, assignment_type: "security_manager")
    refute SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)
  end

  test "doesn't destroy ESM assignment when sync_to_organizations is disabled" do
    @business.update(seats_plan_type: :full)
    GitHub.flipper[:enterprise_teams_security_manager_sync].enable(@business)
    @enterprise_team.sync_to_organizations = "all"
    @enterprise_team.save!
    eta = EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: "security_manager")
    SecurityProduct::EnterpriseSecurityManagerRole.grant!(@enterprise_team)

    put "/enterprises/#{@business.slug}/teams/#{@enterprise_team.slug}", params: {
      teamName: "TnT Team",
      idpGroup: @external_group.id.to_s,
      syncToOrganizations: "false",
    }

    assert_response_bad_request
    response_json = JSON.parse(response.body)
    assert_equal "External groups for enterprise teams are not supported on GHES.", response_json["data"]["error"]
    assert EnterpriseTeamAssignment.find_by(id: eta.id)
    assert SecurityProduct::EnterpriseSecurityManagerRole.granted?(@enterprise_team)
  end
end
