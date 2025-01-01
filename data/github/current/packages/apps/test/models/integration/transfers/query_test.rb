# typed: true
# frozen_string_literal: true

require "test_helper"

class Integration::Transfers::QueryTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @business = create(:business)
  end

  context ".find_target_by_params" do
    test "returns the correct user when transfer_to is User" do
      result = Integration::Transfers::Query.find_target_by_params(transfer_to: "User/#{@user.id}")
      assert_equal @user, result
    end

    test "returns the correct organization when transfer_to is Organization" do
      result = Integration::Transfers::Query.find_target_by_params(transfer_to: "Organization/#{@org.id}")
      assert_equal @org, result
    end

    test "returns the correct business when transfer_to is Business" do
      result = Integration::Transfers::Query.find_target_by_params(transfer_to: "Business/#{@business.id}")
      assert_equal @business, result
    end

    test "returns nil when transfer_to type is unknown" do
      result = Integration::Transfers::Query.find_target_by_params(transfer_to: "Unknown/1")
      assert_nil result
    end
  end
end
