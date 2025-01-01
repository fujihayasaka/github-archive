# typed: true
# frozen_string_literal: true

require "test_helper"

class UserLegalHoldsDependencyTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @user2 = create(:user)
    @org = create(:organization)
    @staff = create :staff_admin_user

    setup_staff_user
  end

  test "create hold on the right user" do
    @user.place_legal_hold(actor: @staff)
    assert @user.legal_hold?
    refute @user2.legal_hold?

    @user.clear_legal_hold(actor: @staff)
    refute @user.reload.legal_hold?

    @user2.place_legal_hold(actor: @staff)
    assert @user2.reload.legal_hold?
    refute @user.legal_hold?

    @user2.clear_legal_hold(actor: @staff)
    refute @user2.reload.legal_hold?

    @org.place_legal_hold(actor: @staff)
    assert @org.reload.legal_hold?
    refute @user.legal_hold?
    refute @user2.legal_hold?

    @org.clear_legal_hold(actor: @staff)
    refute @org.reload.legal_hold?
    refute @user.legal_hold?
    refute @user2.legal_hold?
  end

  test "account can only have one legal hold" do
    @user.place_legal_hold(actor: @staff)
    assert @user.legal_hold?

    refute @user.place_legal_hold(actor: @staff)
  end

  test "can't clear legal hold unless one already exists" do
    refute @user.legal_hold?

    refute @user.clear_legal_hold(actor: @staff)
  end

  test "instruments place_legal_hold for users" do
    events = subscribe "staff.place_legal_hold"

    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        staff_actor: @staff.login,
        staff_actor_id: @staff.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        user: @user.login,
        user_id: @user.id,
      }
    else
      expected_payload = {
        actor: @staff.login,
        actor_id: @staff.id,
        user: @user.login,
        user_id: @user.id,
      }
    end

    @user.place_legal_hold(actor: @staff)
    assert @user.reload.legal_hold?

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments clear_legal_hold for users" do
    @user.place_legal_hold(actor: @staff)
    assert @user.reload.legal_hold?

    events = subscribe "staff.clear_legal_hold"

    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        staff_actor: @staff.login,
        staff_actor_id: @staff.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        user: @user.login,
        user_id: @user.id,
      }
    else
      expected_payload = {
        actor: @staff.login,
        actor_id: @staff.id,
        user: @user.login,
        user_id: @user.id,
      }
    end

    @user.clear_legal_hold(actor: @staff)
    refute @user.reload.legal_hold?

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments place_legal_hold for orgs" do
    events = subscribe "staff.place_legal_hold"

    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        staff_actor: @staff.login,
        staff_actor_id: @staff.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        org: @org.login,
        org_id: @org.id,
      }
    else
      expected_payload = {
        actor: @staff.login,
        actor_id: @staff.id,
        org: @org.login,
        org_id: @org.id,
      }
    end

    @org.place_legal_hold(actor: @staff)
    assert @org.reload.legal_hold?

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "instruments clear_legal_hold for orgs" do
    @org.place_legal_hold(actor: @staff)
    assert @org.reload.legal_hold?

    events = subscribe "staff.clear_legal_hold"

    if GitHub.guard_audit_log_staff_actor?
      expected_payload = {
        staff_actor: @staff.login,
        staff_actor_id: @staff.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        org: @org.login,
        org_id: @org.id,
      }
    else
      expected_payload = {
        actor: @staff.login,
        actor_id: @staff.id,
        org: @org.login,
        org_id: @org.id,
      }
    end

    @org.clear_legal_hold(actor: @staff)
    refute @org.reload.legal_hold?

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end
end
