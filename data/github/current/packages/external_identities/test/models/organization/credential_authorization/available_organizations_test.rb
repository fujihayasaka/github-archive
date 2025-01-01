# typed: true
# frozen_string_literal: true

require "test_helper"

module SharedCredentialMethods
  def available_organizations(actor)
    Organization::CredentialAuthorization.available_organizations(actor)
  end

  def grant(organization:, credential:, actor:)
    Organization::CredentialAuthorization.grant(
      organization: organization, credential: credential, actor: actor
    )
  end
end

class Organization::CredentialAuthorization::AvailableOrganizationsTest < GitHub::TestCase
  include SharedCredentialMethods

  fixtures do
    @org = create(:business_plus_org)
    @org_member = create(:user)
    @org.add_member(@org_member)
    @saml_provider = create :organization_saml_provider, organization: @org
    @external_identity = create :external_identity, provider: @saml_provider, user: @org_member

    @business = create :business
    @other_org = create :organization
    @other_org.add_member @org_member
    @business.add_organization @other_org
    @business_saml_provider = create :business_saml_provider, business: @business
    @business_external_identity = create :external_identity, provider: @business_saml_provider, user: @org_member

    @other_business_org = create :organization
    @business.add_organization @other_business_org
  end

  test "returns nothing if an User actor is not provided" do
    assert_empty available_organizations(nil)
  end

  test "returns nothing if the actor is not a User" do
    assert_empty available_organizations(@org)
  end

  test "returns organizations with an associated external identity" do
    other_org = create :organization
    other_org.add_member(@org_member)

    assert_same_elements [@org, @other_org], available_organizations(@org_member)
  end

  test "only returns organizations with an associated external identity linked to the owning business" do
    other_org = create :organization
    other_org.add_member @org_member

    other_business_org = create :organization
    @business.add_organization other_business_org

    assert_same_elements [@org, @other_org], available_organizations(@org_member)
  end
end

class Organization::CredentialAuthorization::EmuSamlAvailableOrganizationsTest < GitHub::TestCase
  include SharedCredentialMethods
  include ExternalGroupHelpers

  fixtures do
    @org_member = create(:emu)
    @business = @org_member.enterprise_managed_business
    @owner = @business.find_first_emu_owner

    @org = create(:organization, business: @business, admin: @owner)
    @org.add_member(@org_member)

    @other_org = create(:organization, business: @business, admin: @owner)
    @other_org.add_member @org_member

    @other_business_org = create(:organization, business: @business, admin: @owner)
  end

  test "returns organizations with an associated external identity linked to the owning business" do
    assert_same_elements [@org, @other_org], available_organizations(@org_member)
  end

  test "guest collaborators have sso organizations even when they are not direct members" do
    disable_feature_flag(:disable_external_group_team_reconcile_job, @business)

    external_group = create :external_group, :with_members, business: @business, number_of_members: 1
    guest_collaborator = external_group.members.first.external_identity.user
    guest_collaborator.external_identities.first.update!(guest_collaborator: true)

    org = create(:organization, business: @business, admin: @owner)
    team = create(:team, organization: org)

    external_group_team = ExternalGroupTeam.create(external_group: external_group, team: team.reload)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

    # add this user to an externally managed team, which will add the user to the org
    team.add_member guest_collaborator
    reconcile_external_group_teams(external_group: external_group)

    assert team.member? guest_collaborator
    assert org.member? guest_collaborator

    another_org = create(:organization, business: @business, admin: @owner)

    # directly add this user to an org
    another_org.add_member(guest_collaborator)
    assert another_org.member? guest_collaborator

    assert_same_elements [org, another_org], available_organizations(guest_collaborator)
  end
end unless GitHub.single_business_environment?

class Organization::CredentialAuthorization::EmuOidcAvailableOrganizationsTest < GitHub::TestCase
  include SharedCredentialMethods
  include ExternalGroupHelpers

  fixtures do
    @org_member = create(:emu, provider_type: :oidc)
    @business = @org_member.enterprise_managed_business
    @owner = @business.find_first_emu_owner

    @org = create(:organization, business: @business, admin: @owner)
    @org.add_member(@org_member)

    @other_org = create(:organization, business: @business, admin: @owner)
    @other_org.add_member @org_member

    @other_business_org = create(:organization, business: @business, admin: @owner)
  end

  test "returns organizations with an associated external identity linked to the owning business" do
    assert_same_elements [@org, @other_org], available_organizations(@org_member)
  end

  test "guest collaborators have sso organizations" do
    disable_feature_flag(:disable_external_group_team_reconcile_job, @business)

    external_group = create :external_group, :with_members, business: @business, number_of_members: 1
    guest_collaborator = external_group.members.first.external_identity.user
    guest_collaborator.external_identities.first.update!(guest_collaborator: true)

    org = create(:organization, business: @business, admin: @owner)
    team = create(:team, organization: org)

    external_group_team = ExternalGroupTeam.create(external_group: external_group, team: team.reload)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

    # add this user to an externally managed team, which will add the user to the org
    team.add_member guest_collaborator
    reconcile_external_group_teams(external_group: external_group)

    assert team.member? guest_collaborator
    assert org.member? guest_collaborator

    another_org = create(:organization, business: @business, admin: @owner)

    # directly add this user to an org
    another_org.add_member(guest_collaborator)
    assert another_org.member? guest_collaborator

    assert_same_elements [org, another_org], available_organizations(guest_collaborator)
  end
end unless GitHub.single_business_environment?
