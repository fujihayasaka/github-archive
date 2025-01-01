# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/ability_models"

class Ability::OrganizationDependencyTest < GitHub::TestCase
  fixtures do
    @org = create :organization
    @org_on_business_plus = create :business_plus_organization
    @org_on_business_plus_repo = create :repository, :minimal, owner: @org_on_business_plus
  end

  context "user_admin_on_organizations scope" do
    test "includes org admin" do
      admin = @org.admin
      ability = Ability.where(actor_id: admin, subject_id: @org).first

      result = Ability.user_admin_on_organizations(actor_id: [admin])

      assert_includes result, ability
    end

    test "excludes org billing manager" do
      org = create(
        :credit_card_org,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
      )
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admin)
      ability = Ability.where(actor_id: billing_manager, subject_id: org).first

      result = Ability.user_admin_on_organizations(actor_id: [billing_manager])

      refute_includes result, ability
    end

    test "excludes org member" do
      org_member = create(:user)
      @org.add_member(org_member)
      ability = Ability.where(actor_id: org_member, subject_id: @org).first

      result = Ability.user_admin_on_organizations(actor_id: [org_member])

      refute_includes result, ability
    end

    test "excludes team maintainer" do
      team_maintainer = create(:user)
      direct_team = create(:team, organization: @org)
      direct_team.add_member(team_maintainer)
      direct_team.promote_maintainer(team_maintainer)
      ability = Ability.where(actor_id: team_maintainer, subject_id: @org).first

      result = Ability.user_admin_on_organizations(actor_id: [team_maintainer])

      refute_includes result, ability
    end

    test "excludes repo admin" do
      repo_admin = create(:user)
      @org_on_business_plus_repo.add_member(repo_admin, action: :admin)
      ability = Ability.where(actor_id: repo_admin, subject_id: @org_on_business_plus_repo).first

      result = Ability.user_admin_on_organizations(actor_id: [repo_admin])

      refute_includes result, ability
    end

    test "returns empty array when no actor_ids are passed" do
      admin = @org.admin
      ability = Ability.where(actor_id: admin, subject_id: @org).first

      result = Ability.user_admin_on_organizations(actor_id: [])

      refute_includes result, ability
    end
  end
end
