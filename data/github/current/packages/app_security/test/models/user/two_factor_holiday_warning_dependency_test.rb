# typed: true
# frozen_string_literal: true

require "test_helper"

class TwoFactorHolidayDependencyTest < GitHub::TestCase
  include AuthenticationHelpers
  include AuthndClientTestHelpers

  def setup
    @user = create(:user)
    make_two_factor_credential(@user)
    @user.clear_two_factor_holiday_warning_dismissed!
  end

  context "kv operations" do
    test "warning state is persisted" do
      # rubocop:todo GitHub/DoNotUseGlobalKv
      refute GitHub::Authentication::KV.store.get(@user.two_factor_holiday_warning_dismissed_key).value { nil }
      # rubocop:enable GitHub/DoNotUseGlobalKv

      Timecop.freeze do
        @user.two_factor_holiday_warning_dismiss!
        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_equal "true", GitHub::Authentication::KV.store.get(@user.two_factor_holiday_warning_dismissed_key).value { nil }
        # rubocop:enable GitHub/DoNotUseGlobalKv

        @user.clear_two_factor_holiday_warning_dismissed!
        # rubocop:todo GitHub/DoNotUseGlobalKv
        refute GitHub::Authentication::KV.store.get(@user.two_factor_holiday_warning_dismissed_key).value { nil }
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end
    end

    test "warning state has 32 days expiration" do
      # rubocop:todo GitHub/DoNotUseGlobalKv
      refute GitHub::Authentication::KV.store.get(@user.two_factor_holiday_warning_dismissed_key).value { nil }
      # rubocop:enable GitHub/DoNotUseGlobalKv

      now = Time.now
      Timecop.freeze(now) do
        @user.two_factor_holiday_warning_dismiss!
        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_equal "true", GitHub::Authentication::KV.store.get(@user.two_factor_holiday_warning_dismissed_key).value { nil }
        # rubocop:enable GitHub/DoNotUseGlobalKv

        Timecop.travel(now + 33.days) do
          # rubocop:todo GitHub/DoNotUseGlobalKv
          refute GitHub::Authentication::KV.store.get(@user.two_factor_holiday_warning_dismissed_key).value { nil }
          # rubocop:enable GitHub/DoNotUseGlobalKv
        end
      end
    end

    test "ensure dismissed holiday banner KV last the whole banner duration" do
      # rubocop:todo GitHub/DoNotUseGlobalKv
      refute GitHub::Authentication::KV.store.get(@user.two_factor_holiday_warning_dismissed_key).value { nil }
      # rubocop:enable GitHub/DoNotUseGlobalKv

      start_date = Time.new(Time.now.year, 12, 10).utc
      Timecop.freeze(start_date) do
        @user.two_factor_holiday_warning_dismiss!
        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_equal "true", GitHub::Authentication::KV.store.get(@user.two_factor_holiday_warning_dismissed_key).value { nil }
        # rubocop:enable GitHub/DoNotUseGlobalKv
        end_date = (start_date + 1.month).utc
        Timecop.travel(end_date) do
          # rubocop:todo GitHub/DoNotUseGlobalKv
          assert_equal "true", GitHub::Authentication::KV.store.get(@user.two_factor_holiday_warning_dismissed_key).value { nil }
          # rubocop:enable GitHub/DoNotUseGlobalKv
        end
      end
    end

    test "kv helpers read and write state properly" do
      refute @user.two_factor_holiday_warning_dismissed?

      @user.two_factor_holiday_warning_dismiss!
      assert @user.two_factor_holiday_warning_dismissed?

      @user.clear_two_factor_holiday_warning_dismissed!
      refute @user.two_factor_holiday_warning_dismissed?
    end
  end

  context "#should_see_two_factor_holiday_warning?", skip_enterprise: true do
    test "true for eligible users" do
      assert @user.should_see_two_factor_holiday_warning?
    end

    test "false when user has no 2fa" do
      user = create(:user)
      refute user.should_see_two_factor_holiday_warning?
    end

    test "false when backup sms number configured" do
      user = create(:user)
      make_two_factor_credential(user, backup_sms_number: "+1 7736829477")

      refute user.should_see_two_factor_holiday_warning?
    end

    test "false when sms 2fa configured" do
      user = create(:user)
      make_sms_two_factor_credential(user)

      refute user.should_see_two_factor_holiday_warning?
    end

    test "false when user has dismissed the warning already" do
      @user.two_factor_holiday_warning_dismiss!
      refute @user.should_see_two_factor_holiday_warning?
    end

    test "false when user has security keys registered" do
      user = create(:user)
      make_two_factor_credential(user)
      create :security_key, user: user

      refute user.should_see_two_factor_holiday_warning?
    end

    test "false when user has passkeys registered" do
      user = create(:user)
      make_two_factor_credential(user)
      create :trusted_device, user: user, nickname: "test_name"

      refute user.should_see_two_factor_holiday_warning?
    end

    test "false when user has sms and app configured" do
      user = create(:user)
      make_two_factor_credential_both_otp_methods(user)

      refute user.should_see_two_factor_holiday_warning?
    end

    test "true when user has app and gh mobile configured" do
      user = create(:user)
      make_two_factor_credential(user)
      authnd_setup_gh_mobile_auth_user(user)

      assert user.should_see_two_factor_holiday_warning?
    end
  end
end
