# typed: true
# frozen_string_literal: true

require "test_helper"

class ClassroomUserTest < GitHub::TestCase
  test "records are destroyed when the parent user is destroyed" do
    classroom_user = create(:classroom_user)
    classroom_user.user.destroy

    refute ClassroomUser.find_by(id: classroom_user.id)
  end

  context "#verified_teacher?" do
    test "when not a verified teacher" do
      classroom_user = create(:classroom_user)
      refute classroom_user.verified_teacher?
    end

    test "when they are verified" do
      user = create(:user, coupon: create(:coupon, code: "faculty-2020"))
      classroom_user = create(:classroom_user, user: user)
      assert classroom_user.verified_teacher?
    end
  end
end
