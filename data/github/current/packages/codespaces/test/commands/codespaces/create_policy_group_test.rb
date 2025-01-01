# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class CreatePolicyGroupTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      @actor = create(:user)
      @organization = create(:organization, :enterprise_linked)
      @business = @organization.business
      @constraints = [{ name: "codespaces.allowed_machine_types", value: ["standardLinux32gb"] }]
    end

    test "creates a policy with provided constraints" do
      events = subscribe "codespaces.policy_group_created"

      policy_group = Codespaces::CreatePolicyGroup.new(
        name: "Test Policy",
        owner: @organization,
        target_type: :repositories,
        universal_membership: true,
        constraints: @constraints,
        actor: @actor
      ).perform

      assert_equal 1, policy_group.policy_constraints.count
      assert_equal "codespaces.allowed_machine_types", policy_group.policy_constraints.first.name
      assert_equal ["standardLinux32gb"], policy_group.policy_constraints.first.allowed_values

      assert events.count == 1
      assert events.pop.payload >= expected_audit_log_payload(policy_group, [])
      assert_dogstats_increment(1, "codespaces.policy_group.created", "tags" => ["membership:all_repositories"])
    end

    test "creates policy for all repos" do
      events = subscribe "codespaces.policy_group_created"

      policy_group = Codespaces::CreatePolicyGroup.new(
        name: "Test Policy",
        owner: @organization,
        target_type: :repositories,
        universal_membership: true,
        constraints: @constraints,
        actor: @actor
      ).perform

      assert_equal 1, policy_group.policy_group_memberships.count
      assert_equal @organization, policy_group.policy_group_memberships.first.target
      assert events.pop.payload >= expected_audit_log_payload(policy_group, [])
      assert_dogstats_increment(1, "codespaces.policy_group.created", "tags" => ["membership:all_repositories"])
    end

    test "creates policy for selected repos" do
      repo = create(:repository, owner: @organization)

      assert_equal 0, Codespaces::PolicyGroupMembership.where(target: repo).count

      events = subscribe "codespaces.policy_group_created"

      policy_group = Codespaces::CreatePolicyGroup.new(
        name: "Test Policy",
        owner: @organization,
        target_type: :repositories,
        target_ids: [repo.id],
        constraints: @constraints,
        actor: @actor
      ).perform

      assert_equal 1, Codespaces::PolicyGroupMembership.where(target: repo).count
      assert events.pop.payload >= expected_audit_log_payload(policy_group, [repo])
      assert_dogstats_increment(1, "codespaces.policy_group.created", "tags" => ["membership:selected_repositories"])
    end

    test "creates enterprise policy for all orgs" do
      events = subscribe "codespaces.policy_group_created"

      policy_group = Codespaces::CreatePolicyGroup.new(
        name: "Test Policy",
        owner: @business,
        target_type: :organizations,
        universal_membership: true,
        constraints: @constraints,
        actor: @actor,
      ).perform

      assert_equal 1, policy_group.policy_group_memberships.count
      assert_equal @business, policy_group.policy_group_memberships.first.target
      assert events.pop.payload >= expected_audit_log_payload(policy_group, [])
      assert_dogstats_increment(1, "codespaces.policy_group.created", "tags" => ["membership:all_orgs"])
    end

    test "creates enterprise policy for selected orgs" do
      events = subscribe "codespaces.policy_group_created"

      policy_group = Codespaces::CreatePolicyGroup.new(
        name: "Test Policy",
        owner: @business,
        target_type: :organizations,
        target_ids: [@organization.id],
        constraints: @constraints,
        actor: @actor,
      ).perform

      assert_equal 1, policy_group.policy_group_memberships.count
      assert_equal @organization, policy_group.policy_group_memberships.first.target
      assert events.pop.payload >= expected_audit_log_payload(policy_group, [@organization])
      assert_dogstats_increment(1, "codespaces.policy_group.created", "tags" => ["membership:selected_orgs"])
    end

    def expected_audit_log_payload(policy_group, targets)
      payload = {
        actor: @actor.display_login,
        policy_group_id: policy_group.id,
        policy_group_name: policy_group.name,
        policy_constraints: policy_group.policy_constraints.map(&:audit_log_data),
      }
      if policy_group.owner.is_a?(Organization)
        payload.merge!(
          org: @organization.display_login,
          all_repositories: targets.empty?,
          repository_nwos: targets.map(&:name_with_display_owner),
          repository_ids: targets.map(&:id),
        )
      elsif policy_group.owner.is_a?(Business)
        payload.merge!(
          business: @business.name,
          all_organizations: targets.empty?,
          org_logins: targets.map(&:display_login),
          org_ids: targets.map(&:id),
        )
      end
      payload
    end
  end
end
