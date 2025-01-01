# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

require "github/transitions/20250127121011_convert_enterprise_tag_protections"

class ConvertEnterpriseTagProtectionsTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include FineGrainedPermissionsTestHelper

  fixtures do
    RepositoryTagProtectionState::allow_creation_for_tests do
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

      @repos = []
      (0..9).each do |i|
        repo = create(:repository, name: "repo#{i}", owner: @org)

        ["*", "v*.*", "foo", "*.release", "d/e/f"]
          .each { |pattern| repo.create_tag_protection_state(pattern:) }

        @repos.push(repo)
      end
    end
  end

  test "check patterns of auto-imported tag protections" do
    RepositoryTagProtectionState::allow_creation_for_tests do
      repo = create(:repository, name: "repo", owner: @org)

      [
        "*",
        "v*.*",
        "AB",
        "aa",
        "*.release",
        "d/e/f",
      ].each do |pattern|
        repo.create_tag_protection_state(pattern:)
      end

      arguments = GitHub::Transitions::Arguments.new(dry_run: false)
      transition = GitHub::Transitions::ConvertEnterpriseTagProtections.new(arguments)
      batch_items = { repo.id => {} }

      transition.process_batch(batch_items)

      assert_equal 2, repo.rulesets.count

      repo.rulesets.each do |ruleset|
        assert_equal(
          ["~ALL", "refs/tags/*.release", "refs/tags/aa", "refs/tags/AB", "refs/tags/d/e/f", "refs/tags/v*.*"],
          ruleset.conditions[0].parameters["include"]
        )
        assert_equal [], ruleset.conditions[0].parameters["exclude"]
        assert_equal "ref_name", ruleset.conditions[0].target
        assert_equal "fnmatch", ruleset.conditions[0].condition_type
      end
    end
  end

  test "check rule config and bypass list of multiple-ruleset import" do
    RepositoryTagProtectionState::allow_creation_for_tests do
      repo = create(:repository, name: "repo", owner: @org)

      repo.create_tag_protection_state(pattern: "abc")

      arguments = GitHub::Transitions::Arguments.new(dry_run: false)
      transition = GitHub::Transitions::ConvertEnterpriseTagProtections.new(arguments)
      batch_items = { repo.id => {} }

      transition.process_batch(batch_items)

      assert_equal 2, repo.rulesets.count
      assert_same_elements([
        GitHub::Transitions::ConvertEnterpriseTagProtections::AUTO_IMPORT_CREATE_RULESET_NAME,
        GitHub::Transitions::ConvertEnterpriseTagProtections::AUTO_IMPORT_DELETE_RULESET_NAME
      ], repo.rulesets.map { |ruleset| ruleset.name })

      # Check create ruleset

      create_ruleset = repo.rulesets.find_by(name: GitHub::Transitions::ConvertEnterpriseTagProtections::AUTO_IMPORT_CREATE_RULESET_NAME)

      assert_equal(1, create_ruleset.conditions.count)
      assert_same_elements(%w[creation update], create_ruleset.rule_configurations.pluck(:rule_type))

      bypass_role_ids = create_ruleset.bypass_actors.where(actor_type: "RepositoryRole").pluck(:actor_id)

      # All bypass actors on a new import should be Repo roles. No teams, apps, etc. + 1 for org admin
      assert_equal(bypass_role_ids.count + 1, create_ruleset.bypass_actors.count)
      assert create_ruleset.bypass_actors.one? { |actor| actor.type == "OrganizationAdminBypassActor" }

      # Create-ruleset bypassers need create_tag FGP. This means admin, maintain, tag_admin, and tag_creator roles.
      assert_same_elements(
        [Role.admin_role.id, Role.maintain_role.id, @tag_admin_role.id, @tag_creator_role.id],
        bypass_role_ids)

      # Check delete ruleset

      delete_ruleset = repo.rulesets.find_by(name: GitHub::Transitions::ConvertEnterpriseTagProtections::AUTO_IMPORT_DELETE_RULESET_NAME)

      assert_equal(1, delete_ruleset.conditions.count)
      assert_same_elements(%w[deletion update], delete_ruleset.rule_configurations.pluck(:rule_type))

      bypass_role_ids = delete_ruleset.bypass_actors.where(actor_type: "RepositoryRole").pluck(:actor_id)

      # All bypass actors on a new import should be Repo roles. No teams, apps, etc. +1 for org admin
      assert_equal(bypass_role_ids.count + 1, delete_ruleset.bypass_actors.count)
      assert delete_ruleset.bypass_actors.one? { |actor| actor.type == "OrganizationAdminBypassActor" }

      # Delete-ruleset bypassers need delete_tag FGP. This means admin, tag_admin, and tag_deleter roles.
      assert_same_elements(
        [Role.admin_role.id, @tag_admin_role.id, @tag_deleter_role.id],
        bypass_role_ids)
    end
  end

  test "set bypass_mode according to whether the repository is org-owned" do
    RepositoryTagProtectionState::allow_creation_for_tests do
      user_repo = create(:repository, owner: @org_admin)
      user_repo.create_tag_protection_state(pattern: "abc")

      org_repo = create(:repository, owner: @org)
      org_repo.create_tag_protection_state(pattern: "abc")

      arguments = GitHub::Transitions::Arguments.new(dry_run: false)
      transition = GitHub::Transitions::ConvertEnterpriseTagProtections.new(arguments)
      batch_items = { user_repo.id => {}, org_repo.id => {} }

      transition.process_batch(batch_items)

      # user-owned repos do not set org admin bypass
      assert user_repo.rulesets.first.bypass_actors.none? { |actor| actor.type == "OrganizationAdminBypassActor" }

      # org-owned repos set org admin bypass
      assert org_repo.rulesets.first.bypass_actors.one? { |actor| actor.type == "OrganizationAdminBypassActor" }
    end
  end

  test "only repos specified in batch are converted" do
    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::ConvertEnterpriseTagProtections.new(arguments)

    # Batch only asks for 3 specific repos to be converted:
    batch_items = { @repos[1].id => {}, @repos[3].id => {}, @repos[6].id => {} }

    transition.process_batch(batch_items)

    # These 3 repos should have exactly 2 rulesets
    [1, 3, 6].each { |i| assert_equal 2, @repos[i].rulesets.count }
    # The rest should have none
    [0, 2, 4, 5, 7, 8, 9].each { |i| assert_equal 0, @repos[i].rulesets.count }
  end

  test "dry_run? controls whether DB is changed" do
    arguments = GitHub::Transitions::Arguments.new(dry_run: true)
    transition = GitHub::Transitions::ConvertEnterpriseTagProtections.new(arguments)

    batch_items = (0..9).each_with_object(Hash.new) { |i, h| h[@repos[i].id] = {} }

    before_count = RepositoryTagProtectionState.where(enabled: 1).count
    transition.process_batch(batch_items)
    after_count = RepositoryTagProtectionState.where(enabled: 1).count

    # dry_run? == true => tag protections still enabled; no rules created
    assert_equal before_count, after_count
    (0..9).each { |i| assert_equal 0, @repos[i].rulesets.count }

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::ConvertEnterpriseTagProtections.new(arguments)

    transition.process_batch(batch_items)
    after_count = RepositoryTagProtectionState.where(enabled: 1).count

    # dry_run? == false => tag protections disabled; 2 rules created per repo
    assert_equal 0, after_count
    (0..9).each { |i| assert_equal 2, @repos[i].rulesets.count }
  end

  test "only enabled tag protections are converted to rules" do
    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::ConvertEnterpriseTagProtections.new(arguments)

    # disable all tag protection records for @repos[0]
    RepositoryTagProtectionState.where(repository_id: @repos[0].id).each do |tag_prot|
      tag_prot["enabled"] = 0
      tag_prot.save
    end

    batch_items = { @repos[0].id => {}, @repos[1].id => {} }

    transition.process_batch(batch_items)

    # since all tag protections for this repo were disabled, no rulesets got created
    assert_equal 0, @repos[0].rulesets.count
    assert_equal 2, @repos[1].rulesets.count
  end

  test "tag protection patterns are properly converted to rule conditions" do
    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::ConvertEnterpriseTagProtections.new(arguments)

    batch_items = { @repos[0].id => {} }

    transition.process_batch(batch_items)

    rulesets = @repos[0].rulesets

    assert_equal 2, rulesets.count

    rulesets.each do |ruleset|
      assert_equal "enabled", ruleset["enforcement"]

      assert_equal 1, ruleset.conditions.count
      condition = ruleset.conditions.first

      assert_equal [], condition.parameters["exclude"]
      assert_equal ["refs/tags/*.release", "refs/tags/d/e/f", "refs/tags/foo", "refs/tags/v*.*", "~ALL"], condition.parameters["include"].sort
    end
  end
end
