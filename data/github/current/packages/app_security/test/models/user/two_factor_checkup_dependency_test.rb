# typed: true
# frozen_string_literal: true

require "test_helper"

class TwoFactorCheckupTest < GitHub::TestCase
  include AuditLogHelpers

  def setup
    @user = create(:user)
    make_two_factor_credential(@user)
  end

  context "#two_factor_checkup_key" do
    test "returns key" do
      assert_equal @user.two_factor_checkup_key, "user.two_factor_checkup_due_at.#{@user.id}"
    end
  end

  context "two factor checkup KV operations" do
    test "sets KV value" do
      Timecop.freeze(Time.now) do
        @user.set_two_factor_checkup_date

        assert_equal (Time.now.utc + User::TwoFactorCheckupDependency::GRACE_PERIOD_LENGTH).to_s, GitHub::Authentication::KV.store.get(@user.two_factor_checkup_key).value { nil }
      end
    end

    test "clears KV value if session created before 2fa configuration" do
      Timecop.freeze(Time.now) do
        session = new_session(Time.now - 1.day)
        session.save

        @user.set_two_factor_checkup_date
        refute_nil GitHub::Authentication::KV.store.get(@user.two_factor_checkup_key).value { nil }

        @user.clear_two_factor_checkup_date
        assert_nil GitHub::Authentication::KV.store.get(@user.two_factor_checkup_key).value { nil }
        assert_nil GitHub::Authentication::KV.store.get(@user.two_factor_checkup_delay_key).value { nil }
      end
    end

    test "clears KV value if force_hit_kv is true" do
      Timecop.freeze(Time.now) do
        session = new_session(Time.now + 1.day)
        session.save

        @user.set_two_factor_checkup_date
        refute_nil GitHub::Authentication::KV.store.get(@user.two_factor_checkup_key).value { nil }

        @user.clear_two_factor_checkup_date(force_hit_kv = true)
        assert_nil GitHub::Authentication::KV.store.get(@user.two_factor_checkup_key).value { nil }
        assert_nil GitHub::Authentication::KV.store.get(@user.two_factor_checkup_delay_key).value { nil }
      end
    end

    test "does not clear KV value if new session exists after 2fa configuration" do
      Timecop.freeze(Time.now) do
        session = new_session(Time.now + 1.day)
        session.save

        @user.set_two_factor_checkup_date
        refute_nil GitHub::Authentication::KV.store.get(@user.two_factor_checkup_key).value { nil }

        @user.clear_two_factor_checkup_date
        refute_nil GitHub::Authentication::KV.store.get(@user.two_factor_checkup_key).value { nil }
      end
    end

    test "get checkup delay count" do
      @user.set_two_factor_checkup_date
      @user.increment_two_factor_checkup_delay_count
      assert_equal "1", GitHub::Authentication::KV.store.get(@user.two_factor_checkup_delay_key).value { nil }
    end
  end

  context "#is_due_for_two_factor_checkup?" do
    test "returns true if checkup is due" do
      Timecop.freeze(Time.now.utc) do
        @user.set_two_factor_checkup_date
        Timecop.travel(Time.now.utc + User::TwoFactorCheckupDependency::GRACE_PERIOD_LENGTH + 1.day) do
          assert @user.is_due_for_two_factor_checkup?
        end
      end
    end

    test "returns false if checkup is not due" do
      Timecop.freeze(Time.now.utc) do
        @user.set_two_factor_checkup_date
        refute @user.is_due_for_two_factor_checkup?
      end
    end

    test "returns false if two factor is not enabled" do
      @user.two_factor_credential.destroy
      @user.reload
      Timecop.freeze(Time.now.utc) do
        @user.set_two_factor_checkup_date

        Timecop.travel(Time.now.utc + 8.days) do
          refute @user.is_due_for_two_factor_checkup?
        end
      end
    end

    test "returns false if value is missing" do
      refute @user.is_due_for_two_factor_checkup?
    end
  end

  context "#is_flagged_for_two_factor_checkup?" do
    test "returns false if date is not present" do
      refute @user.is_flagged_for_two_factor_checkup?
    end

    test "returns true if date exists" do
      Timecop.freeze(Time.now.utc) do
        @user.set_two_factor_checkup_date
        assert @user.is_flagged_for_two_factor_checkup?
      end
    end

    test "returns false if two factor is not enabled" do
      @user.two_factor_credential.destroy
      @user.reload
      Timecop.freeze(Time.now.utc) do
        @user.set_two_factor_checkup_date

        Timecop.travel(Time.now.utc + 1.day) do
          refute @user.is_flagged_for_two_factor_checkup?
        end
      end
    end
  end

  context "#increment_two_factor_checkup_delay_count" do
    test "returns true and extends date if value is incremented" do
      now = Time.now.utc
      Timecop.freeze(now) do
        @user.set_two_factor_checkup_date
      end

      future_date = now + User::TwoFactorCheckupDependency::GRACE_PERIOD_LENGTH
      Timecop.freeze(future_date) do
        assert @user.increment_two_factor_checkup_delay_count
        expected_date = Time.parse((future_date + 1.day).utc.to_s)
        checkup_date = Time.parse(GitHub::Authentication::KV.store.get(@user.two_factor_checkup_key).value { nil })
        assert_equal expected_date, checkup_date
      end
    end

    test "returns true and extends checkup date to the following day if the original checkup date was a week ago" do
      now = Time.now.utc
      Timecop.freeze(now) do
        @user.set_two_factor_checkup_date
        current_checkup_date = Time.parse(GitHub::Authentication::KV.store.get(@user.two_factor_checkup_key).value { nil })
        expected_checkup_date = Time.parse((now + User::TwoFactorCheckupDependency::GRACE_PERIOD_LENGTH).utc.to_s)
        assert_equal expected_checkup_date, current_checkup_date
      end

      future_date = now + 35.days
      Timecop.freeze(future_date) do
        assert @user.increment_two_factor_checkup_delay_count
        new_checkup_date = Time.parse(GitHub::Authentication::KV.store.get(@user.two_factor_checkup_key).value { nil })
        expected_checkup_date = Time.parse((future_date + 1.day).utc.to_s)
        assert_equal expected_checkup_date, new_checkup_date
      end
    end

    test "returns false if value is already 3 or higher" do
      @user.set_two_factor_checkup_date
      GitHub::Authentication::KV.store.set(@user.two_factor_checkup_delay_key, "3")
      refute @user.increment_two_factor_checkup_delay_count
    end
  end

  def new_session(created_date, attrs = {})
    attrs[:ip] ||= "127.0.0.1"
    attrs[:user_agent] ||= "Rails Test"
    attrs[:user] ||= @user
    attrs[:created_at] ||= created_date
    build(:user_session, attrs)
  end
end
