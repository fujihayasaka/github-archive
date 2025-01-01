# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadBranchProtectionRulePayloadTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @owner = create(:user)
    @actor = create(:user)
    @repo = create :repository, owner: @owner, from_example: :simple
    @repo.add_member @actor, action: :admin
    @rule = create(:protected_branch, {
      repository: @repo,
      creator: @owner,
      name: "*",
    })
    @rule.enable_required_pull_request_reviews(
      dismiss_stale_reviews: true,
      require_code_owner_reviews: true,
      required_approving_review_count: 2
    )
    @rule.update_required_status_checks(strict: true, contexts: %w[s1 s2])
    @rule.save!
    @expected_rule = {
      id: @rule.id,
      repository_id: @repo.id,
      name: "*",
      created_at: @rule.created_at,
      updated_at: @rule.updated_at,
      pull_request_reviews_enforcement_level: "non_admins",
      required_approving_review_count: 2,
      dismiss_stale_reviews_on_push: true,
      require_code_owner_review: true,
      authorized_dismissal_actors_only: false,
      ignore_approvals_from_contributors: false,
      required_status_checks_enforcement_level: "non_admins",
      strict_required_status_checks_policy: true,
      signature_requirement_enforcement_level: "off",
      linear_history_requirement_enforcement_level: "off",
      required_conversation_resolution_level: "off",
      admin_enforced: false,
      allow_force_pushes_enforcement_level: "off",
      allow_deletions_enforcement_level: "off",
      merge_queue_enforcement_level: "off",
      required_deployments_enforcement_level: "off",
      authorized_actors_only: false,
      authorized_actor_names: [],
      required_status_checks: %w[s1 s2],
      create_protected: false,
      require_last_push_approval: false,
      lock_branch_enforcement_level: "off",
    }
  end

  test "required_status_checks is an empty array if no checks are required (for consistency)" do
    @rule.update_required_status_checks(contexts: [])
    @rule.save!
    event = Hook::Event::BranchProtectionRuleEvent.new(
      action: :some_action,
      actor_id: @actor.id,
      protected_branch_id: @rule.id
    )
    payload = Hook::Payload::BranchProtectionRulePayload.new(event).to_hash
    assert_equal [], payload[:rule][:required_status_checks]
  end

  test "payload contains common values for all actions" do
    event = Hook::Event::BranchProtectionRuleEvent.new(
      action: :some_action,
      actor_id: @actor.id,
      protected_branch_id: @rule.id
    )

    payload = Hook::Payload::BranchProtectionRulePayload.new(event).to_hash

    assert_same_elements [:action, :rule, :repository, :sender], payload.keys
    assert_equal :some_action,   payload[:action]
    assert_equal @expected_rule, payload[:rule]
    assert_equal @repo.id,       payload[:repository][:id]
    assert_equal @actor.id,      payload[:sender][:id]
  end

  test "payload contains meaningful changed values (if Rails' previous_changes hash was passed by update)" do
    event = Hook::Event::BranchProtectionRuleEvent.new(
      action: :update,
      actor_id: @actor.id,
      protected_branch_id: @rule.id,
      previous_changes: {
        "name" => ["old-name", "*"],
        "allow_deletions_enforcement_level" => %w[everyone off],
        "updated_at" => [Time.now - 1.minute, @rule.updated_at],     # updated_at should be ignored
        "authorized_actors_only" => [false, true],     # authorized_actors_only should be ignored
        "authorized_dismissal_actors_only" => [false, true],     # authorized_dismissal_actors_only should be ignored
        "block_deletions_enforcement_level" => %w[everyone off],  # "soft" attributes should be ignored
      },
      previous_status_checks_contexts: %w[s2 s3]
    )
    expected_changes = {
      name: {
        from: "old-name"
      },
      allow_deletions_enforcement_level: {
        from: "everyone"
      },
      required_status_checks: {
        from: %w[s2 s3]
      }
    }

    payload = Hook::Payload::BranchProtectionRulePayload.new(event).to_hash

    assert_same_elements [:action, :rule, :repository, :sender, :changes], payload.keys
    assert_equal :update,          payload[:action]
    assert_equal @expected_rule,   payload[:rule]
    assert_equal expected_changes, payload[:changes]
  end

  test "payload contains authorized_dismissal_actors_only when passed in directly" do
    @rule.replace_dismissal_restricted_actors(user_ids: [], team_ids: [])
    @rule.save!
    event = Hook::Event::BranchProtectionRuleEvent.new(
      action: :update,
      actor_id: @actor.id,
      protected_branch_id: @rule.id,
      previous_changes: {
        "name" => ["old-name", "*"],
      },
      previous_authorized_dismissal_actors_only: false,
      previous_status_checks_contexts: %w[s1 s2],
      previous_authorized_actors_only: false
    )
    expected_changes = {
      name: {
        from: "old-name"
      },
      authorized_dismissal_actors_only: {
        from: false
      },
    }

    payload = Hook::Payload::BranchProtectionRulePayload.new(event).to_hash

    assert_same_elements [:action, :rule, :repository, :sender, :changes], payload.keys
    assert_equal :update,          payload[:action]
    assert_equal expected_changes, payload[:changes]
  end

  test "contains lock_allows_fork_syncing when repo is a fork" do
    fork_repo = create(:fork_repository, forker: @actor, fork_repo: @repo)
    rule = create(:protected_branch, {
      repository: fork_repo,
      creator: @actor,
      name: "main",
    })

    event = Hook::Event::BranchProtectionRuleEvent.new(
      action: :some_action,
      actor_id: @actor.id,
      protected_branch_id: rule.id
    )

    payload = Hook::Payload::BranchProtectionRulePayload.new(event).to_hash

    assert payload[:rule].key?(:lock_branch_enforcement_level)
    assert payload[:rule].key?(:lock_allows_fork_syncing)
  end

  test "does not contain lock_allows_fork_syncing when repo is not a fork" do
    event = Hook::Event::BranchProtectionRuleEvent.new(
      action: :some_action,
      actor_id: @actor.id,
      protected_branch_id: @rule.id
    )

    payload = Hook::Payload::BranchProtectionRulePayload.new(event).to_hash

    assert payload[:rule].key?(:lock_branch_enforcement_level)
    refute payload[:rule].key?(:lock_allows_fork_syncing)
  end
end
