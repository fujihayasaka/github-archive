# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryTagProtectionStatesDependencyTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, admin: @org_admin, plan: "business_plus")

    @random_org_user = create(:user)
    @org.add_member(@random_org_user)

    # Roles for create_tag, delete_tag, and both
    @tag_creator_role = create_custom_role(role_name: "tag_creator", owner: @org, base_role: :write,
      fgps: [:create_tag])
    @tag_deleter_role = create_custom_role(role_name: "tag_deleter", owner: @org, base_role: :write,
      fgps: [:delete_tag])
    @tag_admin_role = create_custom_role(role_name: "tag_admin", owner: @org, base_role: :write,
      fgps: [:create_tag, :delete_tag])

    @repo = create(:repository, owner: @org)
  end

  test "check patterns of imported tag protections" do
    RepositoryTagProtectionState::allow_creation_for_tests do
      [
        "*",
        "v*.*",
        "AB",
        "aa",
        "*.release",
        "d/e/f",
      ].each do |pattern|
        @repo.create_tag_protection_state(pattern:)
      end

      import_result = @repo.import_tag_protections_to_rulesets(@org_admin, single_ruleset: true)

      assert_equal([Repository::TagProtectionStatesDependency::SINGLE_RULESET_NAME], import_result.map { |rule| rule.name })

      ruleset = import_result.first

      assert_equal(1, ruleset.conditions.count)
      assert_equal(
        ["~ALL", "refs/tags/*.release", "refs/tags/aa", "refs/tags/AB", "refs/tags/d/e/f", "refs/tags/v*.*"],
        ruleset.conditions[0].parameters["include"]
      )
      assert_equal [], ruleset.conditions[0].parameters["exclude"]
      assert_equal "ref_name", ruleset.conditions[0].target
      assert_equal "fnmatch", ruleset.conditions[0].condition_type
    end
  end

  test "disabled tag protections are ignored by import" do
    RepositoryTagProtectionState::allow_creation_for_tests do
      @repo.create_tag_protection_state(pattern: "abc", enabled: false)

      import_result = @repo.import_tag_protections_to_rulesets(@org_admin, single_ruleset: true)

      assert_equal([], import_result)
    end
  end

  test "check rule config and bypass list of single-ruleset import" do
    RepositoryTagProtectionState::allow_creation_for_tests do
      @repo.create_tag_protection_state(pattern: "abc")

      import_result = @repo.import_tag_protections_to_rulesets(@org_admin, single_ruleset: true)

      assert_equal([Repository::TagProtectionStatesDependency::SINGLE_RULESET_NAME],
        import_result.map { |rule| rule.name })

      ruleset = import_result.first

      assert_equal(1, ruleset.conditions.count)
      assert_same_elements(%w[creation update deletion], ruleset.rule_configurations.pluck(:rule_type))

      bypass_role_ids = ruleset.bypass_actors.where(actor_type: "RepositoryRole").pluck(:actor_id)

      # All bypass actors on a new import should be Repo roles, plus org admins. No teams, apps, etc.
      assert_equal(bypass_role_ids.count + 1, ruleset.bypass_actors.count)
      assert ruleset.bypass_actors.any? { |actor| actor.type == "OrganizationAdminBypassActor" }
      # Single-ruleset bypassers need both create_tag and write_tag FGP. This means admin and tag_admin roles.
      assert_same_elements([Role.admin_role.id, @tag_admin_role.id], bypass_role_ids)
    end
  end

  test "check rule config and bypass list of multiple-ruleset import" do
    RepositoryTagProtectionState::allow_creation_for_tests do
      @repo.create_tag_protection_state(pattern: "abc")

      import_result = @repo.import_tag_protections_to_rulesets(@org_admin, single_ruleset: false)

      assert_same_elements([
        Repository::TagProtectionStatesDependency::CREATE_RULESET_NAME,
        Repository::TagProtectionStatesDependency::DELETE_RULESET_NAME
        ], import_result.map { |ruleset| ruleset.name })

      # Check create ruleset

      create_ruleset = @repo.rulesets.find_by(name: Repository::TagProtectionStatesDependency::CREATE_RULESET_NAME)

      assert_equal(1, create_ruleset.conditions.count)
      assert_same_elements(%w[creation update], create_ruleset.rule_configurations.pluck(:rule_type))

      bypass_role_ids = create_ruleset.bypass_actors.where(actor_type: "RepositoryRole").pluck(:actor_id)

      # All bypass actors on a new import should be Repo roles, plus org admins. No teams, apps, etc.
      assert_equal(bypass_role_ids.count + 1, create_ruleset.bypass_actors.count)
      assert create_ruleset.bypass_actors.any? { |actor| actor.type == "OrganizationAdminBypassActor" }

      # Create-ruleset bypassers need create_tag FGP. This means admin, maintain, tag_admin, and tag_creator roles.
      assert_same_elements(
        [Role.admin_role.id, Role.maintain_role.id, @tag_admin_role.id, @tag_creator_role.id],
        bypass_role_ids)

      # Check delete ruleset

      delete_ruleset = @repo.rulesets.find_by(name: Repository::TagProtectionStatesDependency::DELETE_RULESET_NAME)

      assert_equal(1, delete_ruleset.conditions.count)
      assert_same_elements(%w[deletion update], delete_ruleset.rule_configurations.pluck(:rule_type))

      bypass_role_ids = delete_ruleset.bypass_actors.where(actor_type: "RepositoryRole").pluck(:actor_id)

      # All bypass actors on a new import should be Repo roles, plus org admins. No teams, apps, etc.
      assert_equal(bypass_role_ids.count + 1, delete_ruleset.bypass_actors.count)
      assert delete_ruleset.bypass_actors.any? { |actor| actor.type == "OrganizationAdminBypassActor" }

      # Delete-ruleset bypassers need delete_tag FGP. This means admin, tag_admin, and tag_deleter roles.
      assert_same_elements(
        [Role.admin_role.id, @tag_admin_role.id, @tag_deleter_role.id],
        bypass_role_ids)
    end
  end

  test "set bypass_mode according to whether the repository is org-owned" do
    RepositoryTagProtectionState::allow_creation_for_tests do
      # confirm user-repos do not set org admin bypass
      repo = create(:repository, owner: @org_admin)
      repo.create_tag_protection_state(pattern: "abc")
      import_result = repo.import_tag_protections_to_rulesets(@org_admin, single_ruleset: true)
      ruleset = import_result.first
      assert ruleset.bypass_actors.none? { |actor| actor.type == "OrganizationAdminBypassActor" }

      # confirm org-repos set org admin bypass
      @repo.create_tag_protection_state(pattern: "abc")
      import_result = @repo.import_tag_protections_to_rulesets(@org_admin, single_ruleset: true)
      ruleset = import_result.first
      assert ruleset.bypass_actors.one? { |actor| actor.type == "OrganizationAdminBypassActor" }
    end
  end
end
