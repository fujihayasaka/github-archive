# typed: true
# frozen_string_literal: true

require "test_helper"

class TierResultTest < GitHub::TestCase
  context "tier verbose reasons" do
    test "loads enterprise" do
      result = TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::GITHUB_ENTERPRISE)
      assert_equal ["GitHub Enterprise"], result.verbose_reason
    end

    test "loads TRUSTED_COUPON (multiple)" do
      expected = [
        "Account has non-educational coupon",
        "Oldest owner age was greater than the limit"
      ]
      result = TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::TRUSTED_COUPON)
      assert_equal expected, result.verbose_reason
    end
  end
end
