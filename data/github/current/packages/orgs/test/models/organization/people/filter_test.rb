# typed: true
# frozen_string_literal: true

require "test_helper"

module OrganizationPeopleFilterShared
  def subject
    Organization::People::Filter
  end

  def query(**opts)
    query = opts.fetch(:query, "")
    organization = opts.fetch(:organization, @org)
    current_user = opts.fetch(:current_user, @admin)
    role = opts[:role]

    Organization::People::Query.new(
      query: query,
      organization: organization,
      current_user: current_user,
      role: role,
    )
  end
end

class OrganizationPeopleFilterTest < GitHub::TestCase
  include OrganizationPeopleFilterShared

  fixtures do
    @org = create(:organization)
    @admin = @org.admin
    @member = create(:user, login: "member")
    @member.emails.each(&:verify!)
    @org.add_member(@member)
    @stranger = create(:user)
  end

  context "#call" do
    test "filters users for those without two factor" do
      @member.two_factor_credential = create(:two_factor_credential)
      @member.save!
      q = query
      q.stubs(:two_factor_disabled_scope?).returns(:true)

      res = subject.new(query: q).call
      assert_same_elements User.two_factor_disabled, res
    end

    test "filters users for those with two factor" do
      @member.two_factor_credential = create(:two_factor_credential)
      @member.save!
      q = query
      q.stubs(:two_factor_enabled_scope?).returns(:true)

      res = subject.new(query: q).call
      assert_same_elements [@member], res
    end

    context "two_factor_required_clause" do
      [:required, :warning, :interrupt].each do |state|
        test "filters users for those with two factor requirement state #{state}" do
          TwoFactorRequirementMetadata.create!(user: @member, requirement_reason: "test", state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[state])
          q = query
          q.stubs(:two_factor_required_scope?).returns(:true)

          res = subject.new(query: q).call
          assert_same_elements [@member], res
        end

        test "excludes users with two factor enabled and requirement state #{state}" do
          @member.two_factor_credential = create(:two_factor_credential)
          TwoFactorRequirementMetadata.create!(user: @member, requirement_reason: "test", state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[state])
          q = query
          q.stubs(:two_factor_required_scope?).returns(:true)

          res = subject.new(query: q).call
          assert_empty res
        end
      end

      [:optional, :exempt].each do |state|
        test "excludes users for those with two factor requirement state #{state}" do
          TwoFactorRequirementMetadata.create!(user: @member, requirement_reason: "test", state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[state])
          q = query
          q.stubs(:two_factor_required_scope?).returns(:true)

          res = subject.new(query: q).call
          assert_empty res
        end
      end
    end

    test "filters users by external identity provider id" do
      provider = create(:organization_saml_provider, organization: @org)
      create(:external_identity, user: @member, provider: provider)
      q = query
      q.stubs(:external_identity_linked_scope?).returns(:true)

      res = subject.new(query: q).call
      assert_same_elements [@member], res
    end

    test "filters users by not having an external identity provider" do
      provider = create(:organization_saml_provider, organization: @org)
      create(:external_identity, user: @member, provider: provider)
      q = query
      q.stubs(:external_identity_unlinked_scope?).returns(:true)

      res = subject.new(query: q).call
      refute_includes res, @member
    end

    test "ignores external identity linked filter when no provider exists" do
      q = query
      q.stubs(:external_identity_linked_scope?).returns(:true)

      res = subject.new(query: q).call
      assert_same_elements User.all, res
    end

    test "ignores external identity unlinked filter when no provider exists" do
      q = query
      q.stubs(:external_identity_unlinked_scope?).returns(:true)

      res = subject.new(query: q).call
      assert_same_elements User.all, res
    end

    test "without any filtering, returns all users" do
      res = subject.new(query: query).call
      assert_same_elements User.all, res
    end

    test "does not actually execute a query, but builds a scope" do
      assert_query_count 0 do
        subject.new(query: query).call
      end
    end
  end
end

module ScimManagedOrganizationPeopleFilterSharedTests
  include OrganizationPeopleFilterShared

  def test_filters_users_for_those_with_external_group_membership
    T.bind(self, GitHub::TestCase)
    q = T.unsafe(self).query(organization: @business_org)
    q.stubs(:organization_membership_group_scope?).returns(:true)

    result = T.unsafe(self).subject.new(query: q).call
    assert_same_elements [@organization_mixed_user, @organization_derived_user], result
  end

  def test_filters_users_for_those_with_membership_added_by_admin
    T.bind(self, GitHub::TestCase)
    q = T.unsafe(self).query(organization: @business_org)
    q.stubs(:organization_membership_admin_scope?).returns(:true)

    result = T.unsafe(self).subject.new(query: q).call
    assert_same_elements [@organization_mixed_user, @organization_explicit_user, @admin], result
  end
end

class EMUOrganizationPeopleFilterTest < GitHub::TestCase
  include ScimManagedOrganizationPeopleFilterSharedTests

  fixtures do
    @business = create :business, :enterprise_managed
    create :business_saml_provider, business: @business

    @admin = create :emu, business: @business
    @business_org = create :organization, business: @business, admin: @admin

    @emu_external_group = create :external_group, :with_members, business: @business, number_of_members: 2

    @mixed_membership = @emu_external_group.members[0]
    @organization_mixed_user = @mixed_membership.external_identity.user
    @business_org.add_member(@organization_mixed_user)

    @organization_explicit_user = create :emu, business: @business
    @business_org.add_member(@organization_explicit_user)

    @derived_membership = @emu_external_group.members[1]
    @organization_derived_user = @derived_membership.external_identity.user

    @team = create :team, organization: @business_org
    external_group_team = ExternalGroupTeam.create(external_group: @emu_external_group, team: @team)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)
  end
end unless GitHub.single_business_environment?

class GHESWithSCIMrganizationPeopleFilterTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  include ScimManagedOrganizationPeopleFilterSharedTests

  fixtures do
    setup_saml_auth_mode(with_scim: true)
    @admin = create :ghes_scim_user, :admin
    @provider = @admin.external_identities.first.provider
    @provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")

    @business = @provider.business

    @business_org = create :organization, business: @business, admin: @admin

    @emu_external_group = create :external_group, :with_members, business: @business, number_of_members: 2

    @mixed_membership = @emu_external_group.members[0]
    @organization_mixed_user = @mixed_membership.external_identity.user
    @business_org.add_member(@organization_mixed_user)

    @organization_explicit_user = create :ghes_scim_user, business: @business
    @business_org.add_member(@organization_explicit_user)

    @derived_membership = @emu_external_group.members[1]
    @organization_derived_user = @derived_membership.external_identity.user

    @team = create :team, organization: @business_org
    external_group_team = ExternalGroupTeam.create(external_group: @emu_external_group, team: @team)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end
end if GitHub.single_business_environment?
