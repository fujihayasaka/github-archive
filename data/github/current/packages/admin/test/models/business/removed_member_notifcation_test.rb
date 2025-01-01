# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessRemovedMemberNotificationTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @business = create(:business)
  end

  test "dismiss removes notification after being set" do
    notification = Business::RemovedMemberNotification.new(@business, @user)
    notification.add_two_factor_requirement_non_compliance

    assert_predicate notification, :two_factor_requirement_non_compliance?

    notification.dismiss

    refute_predicate notification, :two_factor_requirement_non_compliance?
  end

  test "dismiss returns false if the business or user are invalid" do
    # bad business
    notification = Business::RemovedMemberNotification.new(nil, @user)
    assert_equal false, notification.dismiss

    # bad user
    notification = Business::RemovedMemberNotification.new(@business, nil)
    assert_equal false, notification.dismiss
  end

  test "dismiss returns true if the notification gets dismissed" do
    notification = Business::RemovedMemberNotification.new(@business, @user)
    refute_predicate notification, :two_factor_requirement_non_compliance?

    notification.add_two_factor_requirement_non_compliance

    assert notification.dismiss
  end

  test "adds a two factor requirement notification for a given business and user" do
    notification = Business::RemovedMemberNotification.new(@business, @user)
    refute_predicate notification, :two_factor_requirement_non_compliance?

    notification.add_two_factor_requirement_non_compliance

    assert_predicate notification, :two_factor_requirement_non_compliance?
  end
end
