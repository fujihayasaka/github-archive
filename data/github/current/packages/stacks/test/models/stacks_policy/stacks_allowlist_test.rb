# typed: true
# frozen_string_literal: true

require "test_helper"

class StacksPolicy::StacksAllowlistTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
  end

  context ".update_or_create_with_patterns" do
    test "creates an allow list and patterns" do
      allowlist = StacksPolicy::StacksAllowlist.update_or_create_with_patterns(@org, patterns: ["mikescoolorg/action@main"], actor: @user)

      assert allowlist.valid?
      assert_equal 1, allowlist.allowed_stacks_patterns.count
    end

    test "uses existing allowlist if it exists" do
      original_allowlist = create(:stacks_policy_allowlist, entity: @org)

      allowlist = StacksPolicy::StacksAllowlist.update_or_create_with_patterns(@org, patterns: ["mikescoolorg/action@main"], actor: @user)

      assert_equal original_allowlist.id, allowlist.id
    end

    test "limits patterns to the max" do
      # To protect from abuse we give a very high limit on patterns.
      StacksPolicy::StacksAllowlist.stub_const(:MAXIMUM_PATTERNS, 2) do
        patterns = %w[patterns are great]
        allowlist = StacksPolicy::StacksAllowlist.update_or_create_with_patterns(@org, patterns: patterns, actor: @user)

        assert allowlist.errors.any?
        assert_equal "cannot be set to more than 2", allowlist.errors.first&.message
        assert_equal 0, allowlist.allowed_stacks_patterns.count
      end
    end

    test "removes patterns if no longer in the list" do
      allowlist = create(:stacks_policy_allowlist, entity: @org)
      pattern_value = "cool/action@main"

      create(:allowed_stacks_pattern, stacksallowlist: allowlist, value: pattern_value)

      StacksPolicy::StacksAllowlist.update_or_create_with_patterns(@org, patterns: ["mikescoolorg/action@main"], actor: @user)

      refute allowlist.allowed_stacks_patterns.pluck(:value).include? pattern_value
    end

    test "very long patterns not allowed" do
      long_pattern = "a" * 300
      allowlist = StacksPolicy::StacksAllowlist.update_or_create_with_patterns(@org, patterns: ["mikescoolorg/action@main", long_pattern], actor: @user)

      assert allowlist.errors.any?
      assert_equal "#{long_pattern} is too long (maximum is 255 characters)", allowlist.errors.first&.message
      assert_equal 1, allowlist.allowed_stacks_patterns.count
    end

    test "verify bulk insert for action patterns" do
      list_of_patterns = (1..(StacksPolicy::StacksAllowlist::MAXIMUM_PATTERNS)).map { |x| "repo/pattern@v#{x}" }
      GitHub::MysqlInstrumenter.with_instrument_and_track do
        allowlist = StacksPolicy::StacksAllowlist.update_or_create_with_patterns(@org, patterns: list_of_patterns, actor: @user)

        assert_equal StacksPolicy::StacksAllowlist::MAXIMUM_PATTERNS, allowlist.allowed_stacks_patterns.count
        assert_equal 1, GitHub::MysqlInstrumenter.queries.map(&:sql).count { |s| s.match(/INSERT INTO `allowed_stacks_patterns`/) }
      end
    end
  end
end
