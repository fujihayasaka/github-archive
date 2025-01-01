# typed: true
# frozen_string_literal: true

require "test_helper"

class ActionsPolicy::AllowlistTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
  end

  context ".update_or_create_with_patterns" do
    test "creates an allow list and patterns" do
      allowlist = ActionsPolicy::Allowlist.update_or_create_with_patterns(@org, patterns: ["mikescoolorg/action@main"], actor: @user)

      assert allowlist.valid?
      assert_equal 1, allowlist.allowed_action_patterns.count
    end

    test "uses existing allowlist if it exists" do
      original_allowlist = create(:actions_policy_allowlist, entity: @org)

      allowlist = ActionsPolicy::Allowlist.update_or_create_with_patterns(@org, patterns: ["mikescoolorg/action@main"], actor: @user)

      assert_equal original_allowlist.id, allowlist.id
    end

    test "limits patterns to the max" do
      ActionsPolicy::Allowlist.stub_const(:MAXIMUM_PATTERNS, 2) do
        patterns = %w[patterns are great]
        allowlist = ActionsPolicy::Allowlist.update_or_create_with_patterns(@org, patterns: patterns, actor: @user)

        assert allowlist.errors.any?
        assert_equal "cannot be set to more than 2", allowlist.errors.first&.message
        assert_equal 0, allowlist.allowed_action_patterns.count
      end
    end

    test "very long patterns not allowed" do
      long_pattern = "a" * 300
      allowlist = ActionsPolicy::Allowlist.update_or_create_with_patterns(@org, patterns: ["mikescoolorg/action@main", long_pattern], actor: @user)

      assert allowlist.errors.any?
      assert_equal "#{long_pattern} is too long (maximum is 255 characters)", allowlist.errors.first&.message
      assert_equal 1, allowlist.allowed_action_patterns.count
    end

    test "verify bulk insert for action patterns" do
      list_of_patterns = ["repo/pattern@v1", "repo/pattern@v2"]
      GitHub::MysqlInstrumenter.reset_stats
      GitHub::MysqlInstrumenter.with_track do
        allowlist = ActionsPolicy::Allowlist.update_or_create_with_patterns(@org, patterns: list_of_patterns, actor: @user)

        assert_equal 2, allowlist.allowed_action_patterns.count
        assert_equal 1, GitHub::MysqlInstrumenter.queries.map(&:sql).count { |s| s.match(/INSERT INTO `allowed_action_patterns`/) }
      end
    end

    test "triggers background job for updating" do
      allowlist = create(:actions_policy_allowlist, entity: @org)
      create(:allowed_action_pattern, allowlist: allowlist, value: "pattern1")
      create(:allowed_action_pattern, allowlist: allowlist, value: "pattern2")
      delete_ids = allowlist.allowed_action_patterns.pluck(:id)
      new_patterns = %w[new_pattern1 new_pattern2]

      ActionsPolicy::Allowlist.stub_const(:MINIMUM_PATTERNS_FOR_ASYNC_UPDATE, 0) do
        Actions::UpdateActionsPatternsJob.expects(:perform_later).with(allowlist.id, delete_ids, new_patterns)

        ActionsPolicy::Allowlist.update_or_create_with_patterns(@org, patterns: new_patterns, actor: @user)
      end
    end

    test "delete the patterns that are not present in new patterns via background job" do
      allowlist = create(:actions_policy_allowlist, entity: @org)
      create(:allowed_action_pattern, allowlist: allowlist, value: "pattern1")
      create(:allowed_action_pattern, allowlist: allowlist, value: "pattern2")
      new_patterns = %w[pattern1 new_pattern1 new_pattern2]
      delete_ids = allowlist.allowed_action_patterns.filter_map { |p| p.id if p.value != "pattern1" }
      ActionsPolicy::Allowlist.stub_const(:MINIMUM_PATTERNS_FOR_ASYNC_UPDATE, 0) do
        Actions::UpdateActionsPatternsJob.expects(:perform_later).with(allowlist.id, delete_ids, %w[new_pattern1 new_pattern2]).once

        ActionsPolicy::Allowlist.update_or_create_with_patterns(@org, patterns: new_patterns, actor: @user)
      end
    end

    test "delete the patterns that are not present in new patterns without background job" do
      allowlist = create(:actions_policy_allowlist, entity: @org)
      create(:allowed_action_pattern, allowlist: allowlist, value: "pattern1")
      create(:allowed_action_pattern, allowlist: allowlist, value: "pattern2")
      new_patterns = %w[pattern1 new_pattern1 new_pattern2]

      ActionsPolicy::Allowlist.update_or_create_with_patterns(@org, patterns: new_patterns, actor: @user)

      refute allowlist.allowed_action_patterns.pluck(:value).include? "pattern2"
    end

    test "returns errors for invalid patterns and inserts only valid patterns via background job" do
      allowlist = create(:actions_policy_allowlist, entity: @org)
      long_pattern = "a" * 300

      ActionsPolicy::Allowlist.stub_const(:MINIMUM_PATTERNS_FOR_ASYNC_UPDATE, 0) do
        Actions::UpdateActionsPatternsJob.expects(:perform_later).with(allowlist.id, [], ["pattern1"]).once
        allowlist = ActionsPolicy::Allowlist.update_or_create_with_patterns(@org, patterns: ["pattern1", long_pattern], actor: @user)

        assert allowlist.errors.any?
        assert_equal "#{long_pattern} is too long (maximum is 255 characters)", allowlist.errors.first&.message
      end
    end

    test "triggers background job to delete patterns when local actions enabled" do
      allowlist = create(:actions_policy_allowlist, entity: @org)
      create(:allowed_action_pattern, allowlist: allowlist, value: "pattern1")
      create(:allowed_action_pattern, allowlist: allowlist, value: "pattern2")
      delete_ids = allowlist.allowed_action_patterns.pluck(:id)

      ActionsPolicy::Allowlist.stub_const(:MINIMUM_PATTERNS_FOR_ASYNC_UPDATE, 0) do
        Actions::UpdateActionsPatternsJob.expects(:perform_later).with(allowlist.id, delete_ids, []).once

        allowlist.enable_local_only

        refute allowlist.github_owned_allowed
        refute allowlist.verified_allowed
      end
    end

    test "verify differential update of patterns without background job" do
      allowlist = create(:actions_policy_allowlist, entity: @org)
      old_pattern = "cool/old-action@main"
      existing_pattern = "cool/existing-action@main"
      new_pattern = "cool/new-action@main"

      create(:allowed_action_pattern, allowlist: allowlist, value: old_pattern)
      create(:allowed_action_pattern, allowlist: allowlist, value: existing_pattern)

      existing_pattern_id = allowlist.allowed_action_patterns.find_by(value: existing_pattern).id

      ActionsPolicy::Allowlist.update_or_create_with_patterns(@org, patterns: [existing_pattern, new_pattern], actor: @user)

      refute allowlist.allowed_action_patterns.pluck(:value).include? old_pattern
      assert allowlist.allowed_action_patterns.pluck(:value).include? existing_pattern
      assert allowlist.allowed_action_patterns.pluck(:value).include? new_pattern

      # this asserts that the existing pattern database id is same as the one we have in the database
      assert_equal allowlist.allowed_action_patterns.find(existing_pattern_id).value, existing_pattern
    end

    test "verify bulk delete for action patterns when local actions enabled without background job" do
      allowlist = create(:actions_policy_allowlist, entity: @org)
      create(:allowed_action_pattern, allowlist: allowlist, value: "pattern1")
      create(:allowed_action_pattern, allowlist: allowlist, value: "pattern2")
      create(:allowed_action_pattern, allowlist: allowlist, value: "pattern3")

      GitHub::MysqlInstrumenter.reset_stats
      GitHub::MysqlInstrumenter.with_track do
        allowlist.enable_local_only

        refute allowlist.github_owned_allowed
        refute allowlist.verified_allowed
        assert_equal 0, allowlist.allowed_action_patterns.count
        assert_equal 1, GitHub::MysqlInstrumenter.queries.map(&:sql).count { |s| s.match(/DELETE FROM `allowed_action_patterns`/) }
      end
    end
  end
end
