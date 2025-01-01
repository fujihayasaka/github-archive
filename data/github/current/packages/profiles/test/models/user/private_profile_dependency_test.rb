# typed: true
# frozen_string_literal: true

require "test_helper"

class PrivateProfileDependencyTest < GitHub::TestCase
  fixtures do
    @public_user = create(:user)
    @private_user = create(:user, private_profile: true)
    @other_user = create(:user)
  end

  context "when the profile owner has enabled private_profile" do
    test "returns false when the viewer is the profile owner" do
      assert_equal false, @private_user.private_profile_for?(@private_user)
    end

    test "returns true when the viewer is a different user" do
      assert_equal true, @private_user.private_profile_for?(@other_user)
    end

    test "returns true when the viewer is anonymous" do
      assert_equal true, @private_user.private_profile_for?(nil)
    end
  end

  context "when the profile owner has not enabled private_profile" do
    test "returns false when the viewer is the profile owner" do
      assert_equal false, @public_user.private_profile_for?(@public_user)
    end

    test "returns false when the viewer is a different user" do
      assert_equal false, @public_user.private_profile_for?(@other_user)
    end

    test "returns false when the viewer is anonymous" do
      assert_equal false, @public_user.private_profile_for?(nil)
    end
  end
end
