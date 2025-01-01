# typed: true
# frozen_string_literal: true

require "test_helper"

class SpamPatternTest < GitHub::TestCase
  setup do
    GitHub.cache.allow = nil
    GitHub.cache.clear
    Spam.enable_spam_pattern_checking
  end

  teardown do
    # In case some other tests don't expect this to be on
    Spam.disable_spam_pattern_checking
  end

  context "SpamPattern" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      skip "spamminess checks are not enabled on Enterprise" unless GitHub.spamminess_check_enabled?
      @pattern        = /ranc/
      @login          = "francis"
      assert @login =~ @pattern  # Make sure the login matches the pattern
    end

    context "enabling and disabling" do
      setup do # rubocop:disable GitHub/NestedSetupTeardown
        @sp = SpamPattern.create(class_name: User, flag: true,
                                 attribute_name: "login",
                                 pattern: /foo/, match_count: 10)
      end

      test "disable! disables it" do
        assert @sp.active?
        @sp.disable!
        refute @sp.reload.active?
      end

      test "enable! enables it" do
        @sp.update_attribute :active, false
        refute @sp.reload.active?
        @sp.enable!
        assert @sp.reload.active?
      end
    end
  end
end

class SpamPatternmemoizedActiveForTest < GitHub::TestCase
  setup do
    @user_pattern = SpamPattern.create(class_name: User,
                                       flag: true,
                                       attribute_name: "first_name",
                                       pattern: /foo/)

    @user_pattern2 = SpamPattern.create(class_name: User,
                                        flag: true,
                                        attribute_name: "last_name",
                                        pattern: /bar/)

  end

  teardown do
    SpamPattern.clear_memoized_active_for
  end

  test "returns the same results for multiple calls within TTL window" do
    memoize_patterns_for(5.seconds) do
      results = SpamPattern.memoized_active_for(User)
      assert_equal 2, results.count

      SpamPattern.create(class_name: User,
                         flag: true,
                         attribute_name: "middle_name",
                         pattern: /baz/)

      5.times do
        assert_equal results, SpamPattern.memoized_active_for(User)
      end
    end
  end

  test "returns the same results as the non-memoized version" do
    memoize_patterns_for(5.seconds) do
      memo_results = SpamPattern.memoized_active_for(User)
      assert_equal 2, memo_results.count
      assert_equal SpamPattern.active_for(User), memo_results
    end
  end

  test "invokes `active_for` once during the TTL period" do
    SpamPattern.expects(:active_for).with(User).once

    memoize_patterns_for(5.seconds) do
      5.times do
        SpamPattern.memoized_active_for(User)
      end
    end
  end

  test "invokes `active_for` after the TTL period has expired" do
    memoize_patterns_for(5.seconds) do
      patterns = SpamPattern.memoized_active_for(User)
      assert_equal 2, patterns.count

      SpamPattern.expects(:active_for).with(User).once

      Timecop.travel(10.seconds.from_now) do
        SpamPattern.memoized_active_for(User)
      end
    end
  end

  private

  def memoize_patterns_for(seconds)
    begin
      original_ttl = GitHub.spam_pattern_memoization_ttl_in_seconds
      GitHub.spam_pattern_memoization_ttl_in_seconds = seconds
      yield
    ensure
      GitHub.spam_pattern_memoization_ttl_in_seconds = original_ttl
    end
  end
end
