# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class OrganizationTeamSyncSerializersTest < Api::SerializerTestCase
  include PlatformTestHelpers::InterfaceHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @owner = create :user, login: "owner"
    @saml_org = create :business_plus_org, login: "saml-org", admin: @owner
    saml_provider = create :organization_saml_provider, organization: @saml_org, issuer: "https://sts.windows.net/a3350e2e-d5fb-4682-b8ed-5cf081a1e841/"
    tenant = create :team_sync_tenant, organization: @saml_org, status: "enabled"
    @enabled_team = create :team, organization: @saml_org
    @now = Time.now
    @mapping = create :team_group_mapping, team: @enabled_team, group_description: "moar cheese pleese", status: "synced", synced_at: @now
  end

  context "#group_hash" do
    test "returns the status and synced_at time of a group_mapping" do
      group = stub("Group", id: "this-id", name: "nombre", description: "A little about me")
      output = group(group)

      assert_equal "this-id", output["group_id"]
      assert_equal "nombre", output["group_name"]
      assert_equal "A little about me", output["group_description"]
    end
  end

  context "#mapping_hash" do
    test "returns status and synced_at time of a group mapping" do
      output = mapping(@mapping)

      assert_equal @mapping.group_id, output["group_id"]
      assert_equal @mapping.group_name, output["group_name"]
      assert_equal "moar cheese pleese", output["group_description"]
      assert_equal "synced", output["status"]
      assert_equal @mapping.synced_at, output["synced_at"]
    end
  end
end if GitHub.team_synchronization_available?

class EmuOrganizationExternalGroupSerializersTest < Api::SerializerTestCase
  include PlatformTestHelpers::InterfaceHelpers
  include AuthenticationHelpers::SAML
  include GitHub::LoggerHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    setup_saml_auth_mode(with_scim: true) if GitHub.single_business_environment?
    @external_group = create :external_group
    @external_group_with_teams = create :external_group, :with_teams, :with_members, number_of_members: 2
  end

  setup do
    setup_saml_auth_mode(with_scim: true) if GitHub.single_business_environment?
  end

  context "#external_group_hash" do
    test "returns the external group in json format" do
      team_ids = @external_group.external_group_teams.pluck(:team_id)
      output = external_group(@external_group, team_ids: team_ids)

      assert_equal @external_group.id, output["group_id"]
      assert_equal @external_group.display_name, output["group_name"]
      assert_equal @external_group.updated_at.iso8601, output["updated_at"]
      assert_nil output["teams"]
      assert_nil output["members"]
    end

    test "returns the external group in json format with teams" do
      team_ids = @external_group.external_group_teams.pluck(:team_id)
      output = external_group(@external_group, team_ids: team_ids, full_group_info: true)

      assert_equal @external_group.id, output["group_id"]
      assert_equal @external_group.display_name, output["group_name"]
      assert_equal @external_group.updated_at.iso8601, output["updated_at"]
      assert_equal [], output["teams"]
      assert_equal [], output["members"]
    end

    test "returns the external group with teams in json format" do
      team_ids = @external_group_with_teams.external_group_teams.pluck(:team_id)
      output = external_group(@external_group_with_teams, team_ids: team_ids, full_group_info: true)

      assert_equal @external_group_with_teams.id, output["group_id"]
      assert_equal @external_group_with_teams.display_name, output["group_name"]
      assert_equal @external_group_with_teams.updated_at.iso8601, output["updated_at"]

      teams_array = @external_group_with_teams.external_group_teams.map do |link|
        {
          "team_id" => link.team.id,
          "team_name" => link.team.name,
        }
      end

      assert_same_elements teams_array, output["teams"]

      members_array = @external_group_with_teams.external_identity_group_memberships.map do |membership|
        user = membership.external_identity.user

        {
          "member_id" => user.id,
          "member_login" => user.login,
          "member_name" => user.profile_name,
          "member_email" => user.profile_email,
        }
      end

      assert_same_elements members_array, output["members"]
    end

    test "returns a single team if not included in team_ids" do
      team_ids = [@external_group_with_teams.external_group_teams.first.team_id]
      output = external_group(@external_group_with_teams, team_ids: team_ids, full_group_info: true)

      assert_equal @external_group_with_teams.id, output["group_id"]
      assert_equal @external_group_with_teams.display_name, output["group_name"]
      assert_equal @external_group_with_teams.updated_at.iso8601, output["updated_at"]

      team = @external_group_with_teams.external_group_teams.first.team
      teams_array = [
        {
          "team_id" => team.id,
          "team_name" => team.name,
        }
      ]

      assert_same_elements teams_array, output["teams"]
      refute_nil output["members"]
      assert_equal 2, output["members"].count
    end

    test "batches members and teams" do
      # Since we stub the batch size to 2, we expect 1 batch to be processed for each (there are 2 external groups and 2 teams)
      base_log = {}
      memberships_log = base_log.merge({ "info.message" => "Processed 1 membership batches" })
      teams_log = base_log.merge({ "info.message" => "Processed 1 team batches" })

      assert_logged(**memberships_log) do
        assert_logged(**teams_log) do
          Api::Serializer::OrganizationTeamSyncDependency.stub_const(:BATCH_SIZE, 2) do
            team_ids = @external_group_with_teams.external_group_teams.pluck(:team_id)
            assert_query_count(10, ignore_feature_flags: true) do
              output = external_group(@external_group_with_teams, team_ids: team_ids, full_group_info: true)

              assert_equal @external_group_with_teams.id, output["group_id"]
              assert_equal @external_group_with_teams.display_name, output["group_name"]
              assert_equal @external_group_with_teams.updated_at.iso8601, output["updated_at"]

              assert_equal 2, output["members"].size
              assert_equal 2, output["teams"].size
            end
          end
        end
      end
    end

    test "succeeds and skips nil users" do
      external_identity = @external_group_with_teams.members.first.external_identity
      deleted_user = external_identity.user
      deleted_user.delete

      team_ids = @external_group_with_teams.external_group_teams.pluck(:team_id)
      output = external_group(@external_group_with_teams, team_ids: team_ids, full_group_info: true)

      members_array = @external_group_with_teams.external_identity_group_memberships.where.not(external_identity_id: external_identity.id).map do |membership|
        user = membership.external_identity.user

        {
          "member_id" => user.id,
          "member_login" => user.login,
          "member_name" => user.profile_name,
          "member_email" => user.profile_email,
        }
      end

      assert_same_elements members_array, output["members"]
    end

    test "succeeds and skips nil teams" do
      team_ids = @external_group_with_teams.external_group_teams.pluck(:team_id)

      deleted_team = @external_group_with_teams.external_group_teams.first.team
      deleted_team.delete

      output = external_group(@external_group_with_teams, team_ids: team_ids, full_group_info: true)

      assert_equal @external_group_with_teams.id, output["group_id"]
      assert_equal @external_group_with_teams.display_name, output["group_name"]
      assert_equal @external_group_with_teams.updated_at.iso8601, output["updated_at"]

      teams_array = @external_group_with_teams.external_group_teams.where.not(team_id: deleted_team.id).map do |link|
        {
          "team_id" => link.team.id,
          "team_name" => link.team.name,
        }
      end

      assert_same_elements teams_array, output["teams"]
    end
  end
end
