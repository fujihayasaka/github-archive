# typed: true
# frozen_string_literal: true

require "test_helper"

class DeceasedUserTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "validations" do
    test "on create, requires a user" do
      missing_user = DeceasedUser.new
      refute_predicate missing_user, :valid?
    end

    test "on create, requires user to be unique" do
      valid_deceased_user = DeceasedUser.create(user: @user)
      assert_predicate valid_deceased_user, :valid?

      duplicate_deceased_user = DeceasedUser.create(user: @user)
      refute_predicate duplicate_deceased_user, :valid?
    end
  end

  test "creating a deceased user instruments an audit log" do
    events = subscribe "deceased_user.create"

    @user.mark_deceased

    expected_payload = {
      user: @user.login,
      user_id: @user.id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end
end
