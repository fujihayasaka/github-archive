# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::UserTierCacheTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
  end

  setup do
    @tier_result = TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason")
  end

  context "#set" do
    test "does not set any values if user_id is nil" do
      GitHub::KV.any_instance.expects(:set).never

      Codespaces::UserTierCache.set(
        user_id: nil,
        tier_result: @tier_result
      )
    end

    test "does not set any values if tier_result is nil" do
      GitHub::KV.any_instance.expects(:set).never

      Codespaces::UserTierCache.set(
        user_id: @user.id,
        tier_result: nil
      )
    end

    test "sets values when there is both a user_id and tier_result present" do
      Codespaces::UserTierCache.set(user_id: @user.id, tier_result: @tier_result)

      assert_equal @tier_result, Codespaces::UserTierCache.get(user_id: @user.id)
    end
  end

  context "#get" do
    test "returns stored value when present" do
      Codespaces::UserTierCache.set(user_id: @user.id, tier_result: @tier_result)
      get_result = Codespaces::UserTierCache.get(user_id: @user.id)

      assert_equal @tier_result.tier, get_result.tier
      assert_equal @tier_result.reason, get_result.reason
    end

    test "returns nil for user_id that is not set" do
      assert_nil Codespaces::UserTierCache.get(user_id: 23)
    end
  end

  context "#key" do
    test "it returns a key for a given user" do
      user_id = @user.id

      assert_equal "codespaces:user_tier:v1:#{user_id}", Codespaces::UserTierCache.key(user_id: user_id)
    end
  end
end
