# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdateUserHiddenTest < GitHub::TestCase
  spammy_only

  fixtures do
    @follower = create(:user)
    @followed = create(:user)
    @follower.follow(@followed)
    @follower.followings.update_all(user_hidden: true)
  end

  context "user_ids_for_mismatches" do
    test "includes followers where the followed user is not spammy" do
      assert_includes Spam::UpdateUserHidden.user_ids_for_mismatches(updated_since: 1.day.ago), @follower.id
    end

    test "excludes followers where the followed user is spammy" do
      @followed.update!(spammy: true)

      refute_includes Spam::UpdateUserHidden.user_ids_for_mismatches(updated_since: 1.day.ago), @follower.id
    end
  end
end
