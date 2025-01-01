# typed: true
# frozen_string_literal: true

require "test_helper"

class ActionsPolicyAccessPolicyDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org)

    @business_org = create(:enterprise_linked_organization)
    @business = @business_org.business
    @business_owner = @business.owners.first
    @business_repo = create(:repository, owner: @business_org)
  end

  context "#highest_level_allowlist" do
    test "returns Business allow list when set, ignores lower level" do
      @business.create_actions_allowlist
      @business_org.create_actions_allowlist
      @business_repo.create_actions_allowlist

      # Always returns the business allow list, ignores others.
      assert_equal @business, @business.highest_level_allowlist.entity
      assert_equal @business, @business_org.highest_level_allowlist.entity
      assert_equal @business, @business_repo.highest_level_allowlist.entity
    end

    test "returns Org allow list when it is highest set" do
      @business_org.create_actions_allowlist
      @business_repo.create_actions_allowlist

      assert_nil @business.highest_level_allowlist
      assert_equal @business_org, @business_org.highest_level_allowlist.entity
      assert_equal @business_org, @business_repo.highest_level_allowlist.entity
    end

    test "returns Repo allow list when nothing higher is set" do
      @business_repo.create_actions_allowlist

      assert_nil @business.highest_level_allowlist
      assert_nil @business_org.highest_level_allowlist
      assert_equal @business_repo, @business_repo.highest_level_allowlist.entity
    end
  end

  context "#allows_all_actions?" do
    test "false if actions are disabled by the entity admin" do
      @repo.disable_actions(actor: @org.admin)
      refute @repo.reload.allows_all_actions?
    end

    test "false if actions were disabled by the entity's owner" do
      @org.disable_actions(actor: @org.admin)
      @repo.enable_actions(actor: @org.admin)
      refute @repo.reload.allows_all_actions?
    end

    test "false if actions are enabled but there's an allowlist" do
      @repo.enable_actions(actor: @org.admin)
      @repo.create_actions_allowlist
      refute @repo.reload.allows_all_actions?
    end

    test "false if actions are enabled but the owner has an allowlist" do
      @org.enable_actions(actor: @org.admin)
      @org.create_actions_allowlist(github_owned_allowed: true)
      @repo.enable_actions(actor: @org.admin)

      refute @repo.reload.allows_all_actions?
    end

    test "true if actions are enabled and there's no allowlist" do
      @repo.enable_actions(actor: @org.admin)
      assert @repo.reload.allows_all_actions?
    end
  end

  context "#allows_local_actions_only?" do
    test "true if it has an allowlist that is local Actions only" do
      @org.create_actions_allowlist
      assert @org.allows_local_actions_only?
    end

    test "false if it has an allowlist includes enables other action types including local" do
      @org.create_actions_allowlist(github_owned_allowed: true)
      refute @org.allows_local_actions_only?
    end

    test "false if there is no associated allowlist" do
      refute @org.allows_local_actions_only?
      refute @repo.allows_local_actions_only?
    end

    test "delegates to its owner allowlist with local only if it doesn't have one itself" do
      org_allowlist = @org.create_actions_allowlist
      assert @repo.reload.allows_local_actions_only?
    end

    test "delegates to its owner allowlist with specified allowed if it doesn't have one itself" do
      org_allowlist = @org.create_actions_allowlist(github_owned_allowed: true)
      refute @repo.reload.allows_local_actions_only?
    end

    test "false if owner disabled actions" do
      @org.disable_actions(actor: @org.admin)
      @repo.create_actions_allowlist

      refute @repo.reload.allows_local_actions_only?
    end

    test "true if owner allows local only even if entity says specified" do
      @org.create_actions_allowlist
      @repo.create_actions_allowlist(github_owned_allowed: true)

      assert @repo.reload.allows_local_actions_only?
    end

    test "true if owner allows specified but entity allows local only" do
      @org.create_actions_allowlist(github_owned_allowed: true)
      @repo.create_actions_allowlist

      assert @repo.reload.allows_local_actions_only?
    end
  end

  context "#allows_specified_actions?" do
    test "true if it has an allowlist that enabled GitHub-owned actions" do
      @org.create_actions_allowlist(github_owned_allowed: true, verified_allowed: false)
      assert @org.reload.allows_specified_actions?
    end

    test "true if it has an allowlist that enabled verified actions" do
      @org.create_actions_allowlist(github_owned_allowed: false, verified_allowed: true)
      assert @org.reload.allows_specified_actions?
    end

    test "true if it has an allowlist that includes allowed action patterns" do
      allowlist = @org.create_actions_allowlist(github_owned_allowed: false, verified_allowed: false)
      allowlist.allowed_action_patterns.create(value: "monalisa/*")
      assert @org.reload.allows_specified_actions?
    end

    test "true for any combination of GitHub-owned, verified, or patterns" do
      @org.create_actions_allowlist.update(github_owned_allowed: true, verified_allowed: false)
      assert @org.reload.allows_specified_actions?
    end

    test "false if there is no associated allowlist" do
      refute @org.allows_specified_actions?
      refute @repo.allows_specified_actions?
    end

    test "delegates to its owner allowlist if it doesn't have one itself" do
      org_allowlist = @org.create_actions_allowlist(github_owned_allowed: true, verified_allowed: false)
      assert @repo.reload.allows_specified_actions?

      org_allowlist.update(github_owned_allowed: false, verified_allowed: false)
      refute @repo.reload.allows_specified_actions?
    end

    test "false if owner disabled actions" do
      @org.disable_actions(actor: @org.admin)
      @repo.create_actions_allowlist(github_owned_allowed: true, verified_allowed: true)

      @repo.reload
      refute @repo.allows_specified_actions?
      assert @repo.actions_disabled?
    end

    test "false if allowlist exists but owner only allows local actions" do
      @org.enable_actions(actor: @org.admin)
      @org.enable_local_actions_only
      @repo.create_actions_allowlist(github_owned_allowed: true, verified_allowed: true)

      @repo.reload
      refute @repo.allows_specified_actions?
    end

    test "true if owner allows all actions but entity allows specified only" do
      @org.enable_actions(actor: @org.admin)
      @repo.create_actions_allowlist(verified_allowed: true)

      assert @repo.reload.allows_specified_actions?
    end

    test "true if either the owner or repo allows specified actions" do
      @org.create_actions_allowlist(github_owned_allowed: true)
      @repo.create_actions_allowlist(verified_allowed: true)

      assert @repo.reload.allows_specified_actions?
    end
  end

  context "#allows_github_owned_actions?" do
    test "true if it has an allowlist that includes local Actions" do
      @org.create_actions_allowlist(github_owned_allowed: true)
      assert @org.allows_github_owned_actions?
    end

    test "false if it has an allowlist that excludes local Actions" do
      @org.create_actions_allowlist(github_owned_allowed: false)
      refute @org.allows_github_owned_actions?
    end

    test "false if there is no associated allowlist" do
      refute @org.allows_github_owned_actions?
      refute @repo.allows_github_owned_actions?
    end

    test "delegates to its owner allowlist if it doesn't have one itself" do
      org_allowlist = @org.create_actions_allowlist(github_owned_allowed: true)
      assert @repo.reload.allows_github_owned_actions?

      org_allowlist.update(github_owned_allowed: false)
      refute @repo.reload.allows_github_owned_actions?
    end

    test "owner allowlist takes precedence if both owner and entity has allowlist" do
      @org.create_actions_allowlist(github_owned_allowed: true)
      @repo.create_actions_allowlist(verified_allowed: true)

      assert @repo.reload.allows_github_owned_actions?
      refute @repo.reload.allows_verified_actions?
    end
  end

  context "#allows_verified_actions?" do
    test "true if it has an allowlist that includes local Actions" do
      @org.create_actions_allowlist(verified_allowed: true)
      assert @org.allows_verified_actions?
      assert @repo.allows_verified_actions?
    end

    test "false if it has an allowlist that excludes local Actions" do
      @org.create_actions_allowlist(verified_allowed: false)
      refute @org.allows_verified_actions?
      refute @repo.allows_verified_actions?
    end

    test "false if there is no associated allowlist" do
      refute @org.allows_verified_actions?
      refute @repo.allows_verified_actions?
    end

    test "delegates to its owner allowlist if it doesn't have one itself" do
      org_allowlist = @org.create_actions_allowlist(verified_allowed: true)
      assert @repo.reload.allows_verified_actions?

      org_allowlist.update(verified_allowed: false)
      refute @repo.reload.allows_verified_actions?
    end

    test "owner allowlist takes precedence if both owner and entity has allowlist" do
      @org.create_actions_allowlist(verified_allowed: true)
      @repo.create_actions_allowlist(github_owned_allowed: true)

      assert @repo.reload.allows_verified_actions?
      refute @repo.reload.allows_github_owned_actions?
    end
  end

  context "#owner_allows_local_actions_only?" do
    test "true if owner has an allowlist that is local Actions only" do
      @org.create_actions_allowlist
      assert @repo.owner_allows_local_actions_only?
    end

    test "false if it has an allowlist includes enables other action types" do
      @org.create_actions_allowlist(github_owned_allowed: true)
      refute @repo.owner_allows_local_actions_only?
    end

    test "false if there is no associated allowlist" do
      refute @repo.owner_allows_local_actions_only?
    end

    test "true if highest owner has an allowlist that is local actions only" do
      @business.create_actions_allowlist # Local only
      @business_org.create_actions_allowlist(verified_allowed: true) # Not local only

      assert @business_repo.owner_allows_local_actions_only?
    end
  end

  context "#enable_local_actions_only" do
    test "updates existing allowlist settings to be local only" do
      @org.create_actions_allowlist(verified_allowed: true)
      @org.enable_local_actions_only
      assert @org.reload.allows_local_actions_only?
    end

    test "creates a new allowlist to set to local only" do
      assert_changes -> { ActionsPolicy::Allowlist.count }, from: 0, to: 1 do
        @org.enable_local_actions_only
      end

      assert @org.reload.allows_local_actions_only?
    end

    test "can restrict to local actions if owner allows specified actions" do
      @org.create_actions_allowlist(github_owned_allowed: true, verified_allowed: true)

      assert_changes -> { ActionsPolicy::Allowlist.count }, from: 1, to: 2 do
        @repo.enable_local_actions_only
      end

      assert @repo.reload.allows_local_actions_only?
    end
  end

  context "#actions_disabled_at_any_level?" do
    test "true when actions is disabled by the entity admin" do
      @repo.disable_actions(actor: @org.admin)
      assert @repo.reload.actions_disabled_at_any_level?
    end

    test "true when actions is disabled by entity owner" do
      @org.disable_actions(actor: @org.admin)
      assert @repo.reload.actions_disabled_at_any_level?
    end

    test "true when actions is disabled by a higher level owner" do
      @business.disable_actions(actor: @business_owner)
      assert @business_repo.reload.actions_disabled_at_any_level?
    end

    test "true when entity was not selected to allow actions" do
      @org.enable_actions_for_selected(actor: @org.admin)
      @repo.disallow_actions(actor: @org.admin)

      assert @repo.reload.actions_disabled_at_any_level?
    end

    test "true when entity owner was not selected to allow actions" do
      @business.enable_actions_for_selected(actor: @business_owner)
      @business_org.disallow_actions(actor: @business_owner)

      assert @business_repo.reload.actions_disabled_at_any_level?
    end

    test "false when actions is enabled for everyone down the hierarchy" do
      @business.enable_actions(actor: @business_owner)
      @business_org.enable_actions(actor: @business_org.admin)
      @business_repo.enable_actions(actor: @business_org.admin)

      refute @business_repo.reload.actions_disabled_at_any_level?
    end

    test "false when actions is enabled for a specific sub-entities" do
      @business.enable_actions_for_selected(actor: @business_owner)
      @business_org.allow_actions(actor: @business_owner)
      @business_org.enable_actions_for_selected(actor: @business_org.admin)
      @business_repo.allow_actions(actor: @business_org.admin)
      @business_repo.enable_actions(actor: @business_org.admin)

      refute @business_repo.reload.actions_disabled_at_any_level?
    end
  end
end
