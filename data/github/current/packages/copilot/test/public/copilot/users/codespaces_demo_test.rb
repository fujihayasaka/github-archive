# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Users::CodespacesDemoTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @user = create(:user)
  end

  setup do
    @copilot_user = Copilot::User.new(@user)
  end

  context "#codespaces_demo_session_active?" do
    test "returns true if this is your first visit (0 minutes)" do
      # fake the increment_codespaces_demo_session_value! call
      Copilot.redis.set(@copilot_user.codespaces_demo_key, Copilot::CODESPACES_DEMO_FIRST_VALUE, ex: 30.minutes.from_now.to_i)

      assert @copilot_user.codespaces_demo_session_active?
    end

    test "returns true if this is your second visit (30 minutes)" do
      # fake the increment_codespaces_demo_session_value! call
      Copilot.redis.set(@copilot_user.codespaces_demo_key, Copilot::CODESPACES_DEMO_SECOND_VALUE, ex: 30.minutes.from_now.to_i)

      assert @copilot_user.codespaces_demo_session_active?
    end

    test "returns true if this is your third visit (60 minutes)" do
      # fake the increment_codespaces_demo_session_value! call
      Copilot.redis.set(@copilot_user.codespaces_demo_key, Copilot::CODESPACES_DEMO_THIRD_VALUE, ex: 30.minutes.from_now.to_i)

      assert @copilot_user.codespaces_demo_session_active?
    end

    test "returns true if this is your fourth visit (90 minutes)" do
      # fake the increment_codespaces_demo_session_value! call
      Copilot.redis.set(@copilot_user.codespaces_demo_key, Copilot::CODESPACES_DEMO_FOURTH_VALUE, ex: 30.minutes.from_now.to_i)

      assert @copilot_user.codespaces_demo_session_active?
    end

    test "returns FALSE if this is your fifth visit or later (120 minutes)" do
      # fake the increment_codespaces_demo_session_value! call
      Copilot.redis.set(@copilot_user.codespaces_demo_key, Copilot::CODESPACES_DEMO_FINAL_VALUE, ex: 30.minutes.from_now.to_i)

      refute @copilot_user.codespaces_demo_session_active?
    end
  end

  context "#increment_codespaces_demo_session_value!" do
    test "sets to first value if this is your first visit (0 minutes)" do
      Copilot.redis.del(@copilot_user.codespaces_demo_key) # make nil
      @copilot_user.increment_codespaces_demo_session_value!

      assert_equal Copilot::CODESPACES_DEMO_FIRST_VALUE, @copilot_user.codespaces_demo_session_value
    end

    test "sets to second value if this is your second visit (30 minutes)" do
      Copilot.redis.set(@copilot_user.codespaces_demo_key, Copilot::CODESPACES_DEMO_FIRST_VALUE, ex: 30.minutes.from_now.to_i)
      @copilot_user.increment_codespaces_demo_session_value!

      assert_equal Copilot::CODESPACES_DEMO_SECOND_VALUE, @copilot_user.codespaces_demo_session_value
    end

    test "sets to third value if this is your third visit (60 minutes)" do
      Copilot.redis.set(@copilot_user.codespaces_demo_key, Copilot::CODESPACES_DEMO_SECOND_VALUE, ex: 30.minutes.from_now.to_i)
      @copilot_user.increment_codespaces_demo_session_value!

      assert_equal Copilot::CODESPACES_DEMO_THIRD_VALUE, @copilot_user.codespaces_demo_session_value
    end

    test "sets to fourth value if this is your fourth visit (90 minutes)" do
      Copilot.redis.set(@copilot_user.codespaces_demo_key, Copilot::CODESPACES_DEMO_THIRD_VALUE, ex: 30.minutes.from_now.to_i)
      @copilot_user.increment_codespaces_demo_session_value!

      assert_equal Copilot::CODESPACES_DEMO_FOURTH_VALUE, @copilot_user.codespaces_demo_session_value
    end

    test "sets to final value if this is your fifth visit (120 minutes)" do
      Copilot.redis.set(@copilot_user.codespaces_demo_key, Copilot::CODESPACES_DEMO_FOURTH_VALUE, ex: 30.minutes.from_now.to_i)
      @copilot_user.increment_codespaces_demo_session_value!

      assert_equal Copilot::CODESPACES_DEMO_FINAL_VALUE, @copilot_user.codespaces_demo_session_value
    end

    test "changes nothing when final" do
      Copilot.redis.set(@copilot_user.codespaces_demo_key, Copilot::CODESPACES_DEMO_FINAL_VALUE, ex: 30.minutes.from_now.to_i)
      @copilot_user.increment_codespaces_demo_session_value!

      assert_equal Copilot::CODESPACES_DEMO_FINAL_VALUE, @copilot_user.codespaces_demo_session_value
    end
  end
end if GitHub.copilot_enabled?
