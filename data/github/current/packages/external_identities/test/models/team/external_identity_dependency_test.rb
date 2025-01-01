# typed: true
# frozen_string_literal: true

require "test_helper"

class Team::ExternalIdentityDependencyTest < GitHub::TestCase
  context "teams#matched_external_members" do
    test "does not find matches " do
      external_team = create(:team)
      create(:team_group_mapping, team: external_team)
      create(:team_sync_tenant, :azuread, organization: external_team.organization)

      external_members = [
        GroupSyncer::V1::GroupMember.new(id: "62dfce2e-4058-408f-be88-38047768a764", name: "Azure User"),
        GroupSyncer::V1::GroupMember.new(id: "d80c1e47-d561-4efa-8fbb-69975e88893b", name: "Okta User"),
      ]
      no_matches_found = external_team.matched_external_members(external_members)
      assert_predicate no_matches_found, :empty?
    end

    test "matches members by their Azure AD SAML attributes" do
      external_team = create(:team)
      create(:team_group_mapping, team: external_team)
      create(:team_sync_tenant, :azuread, organization: external_team.organization)

      azure_user = create(:user)
      create(:external_identity, user: azure_user,
             saml_user_data: Platform::Provisioning::SamlUserData.new(
               [{ "name" => "http://schemas.microsoft.com/identity/claims/objectidentifier", "value" => "62dfce2e-4058-408f-be88-38047768a764" }],
      ))
      external_team.add_member(azure_user)

      external_members = [
        GroupSyncer::V1::GroupMember.new(id: "62dfce2e-4058-408f-be88-38047768a764", name: "Jeff"),
        GroupSyncer::V1::GroupMember.new(id: "d80c1e47-d561-4efa-8fbb-69975e88893b", name: "Diego"),
      ]
      saml_matches_found = external_team.matched_external_members(external_members)
      assert_equal [azure_user], saml_matches_found
    end

    test "matches members by their SCIM attributes" do
      external_team = create(:team)
      create(:team_group_mapping, team: external_team)
      create(:team_sync_tenant, :okta, organization: external_team.organization)

      scim_user = create(:user)

      create(:external_identity, user: scim_user,
             scim_user_data: Platform::Provisioning::ScimUserData.new(
               [{ "name" => "externalId", "value" => "d80c1e47-d561-4efa-8fbb-69975e88893b" }],
      ))
      external_team.add_member(scim_user)

      external_members = [
        GroupSyncer::V1::GroupMember.new(id: "62dfce2e-4058-408f-be88-38047768a764", name: "Dora"),
        GroupSyncer::V1::GroupMember.new(id: "d80c1e47-d561-4efa-8fbb-69975e88893b", name: "Boots"),
      ]
      scim_matches_found = external_team.matched_external_members(external_members)
      assert_equal [scim_user], scim_matches_found
    end
  end
end if GitHub.team_synchronization_available?
