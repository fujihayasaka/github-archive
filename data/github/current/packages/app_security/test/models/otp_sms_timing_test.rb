# typed: true
# frozen_string_literal: true

require "test_helper"

class OtpSmsTimingTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @test_timing = OtpSmsTiming.create(timing_key: "testtest", provider: "test", user_id: @user.id)
    @other_timing = OtpSmsTiming.create(timing_key: "othertest", provider: "other", user_id: @user.id)
  end

  context ".by_timing_key" do
    test "returns the timings matching the timing_key" do
      assert_equal 2, OtpSmsTiming.count
      timing = OtpSmsTiming.by_timing_key("testtest")
      assert_equal timing.id, @test_timing.id
    end
  end

  context "expired_outstanding" do
    test "returns the keys which have expired" do
      assert_equal 0, OtpSmsTiming.expired_outstanding.count
      Timecop.freeze(Time.now + (TwoFactorCredential::ALLOWABLE_DRIFT * 2)) do
        assert_equal 2, OtpSmsTiming.expired_outstanding.count
      end
    end
  end

  context ".record_outstanding" do
    test "creates a record" do
      assert_equal 2, OtpSmsTiming.count
      OtpSmsTiming.record_outstanding("test", "thing", @user.id)
      assert_equal 3, OtpSmsTiming.count
    end
  end

  context ".resolve" do
    test "destroys a record" do
      assert_equal 2, OtpSmsTiming.count
      OtpSmsTiming.resolve(@test_timing.id)
      assert_equal 1, OtpSmsTiming.count
    end
  end
end
