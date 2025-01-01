# typed: true
# frozen_string_literal: true

require "test_helper"

class TrialConfigHelperTest < GitHub::TestCase
  setup do
    @helper = Configurable::TrialConfigHelper.new(rec: create(:business), sku_name: "secret_protection", max_days: 90)
  end

  test "enable_trial works" do
    # check preconditions
    helper = T.let(@helper, Configurable::TrialConfigHelper)
    refute helper.trial_enabled?
    assert_nil helper.number_of_days
    assert_nil helper.expires_at

    # enable trial
    start_date = Date.current
    days = 30
    helper.enable_trial(actor: User.ghost, start_date: start_date, days: days)

    # check stuff
    assert helper.trial_enabled?
    assert_equal days, helper.number_of_days
    assert_equal start_date + days.days, helper.expires_at
  end

  test "set_number_of_days works with no trial enabled" do
    # call it
    helper = T.let(@helper, Configurable::TrialConfigHelper)
    days = 10
    helper.set_number_of_days(actor: User.ghost, days: days)

    # check stuff
    refute helper.trial_enabled?
    assert_equal days, helper.number_of_days
    assert_nil helper.expires_at
  end

  test "set_number_of_days works with trial enabled" do
    # enable trial
    helper = T.let(@helper, Configurable::TrialConfigHelper)
    start_date = Date.current
    days = 30
    helper.enable_trial(actor: User.ghost, start_date: start_date, days: days)

    # call it
    new_days = 10
    helper.set_number_of_days(actor: User.ghost, days: new_days)

    # check stuff
    assert helper.trial_enabled?
    assert_equal new_days, helper.number_of_days
    assert_equal start_date + new_days.days, helper.expires_at
  end

  test "expired trial is still enabled, 1" do
    # make expired trial
    helper = T.let(@helper, Configurable::TrialConfigHelper)
    now = Date.current
    start_date_days_before_now = 30
    helper.enable_trial(actor: User.ghost, start_date: now - start_date_days_before_now.days, days: start_date_days_before_now - 1)

    # check stuff
    assert T.must(helper.expires_at) < now
    assert helper.trial_enabled?
  end

  test "expired trial is still enabled, 2" do
    # make unexpired trial
    helper = T.let(@helper, Configurable::TrialConfigHelper)
    now = Date.current
    start_date_days_before_now = 30
    helper.enable_trial(actor: User.ghost, start_date: now - start_date_days_before_now.days, days: start_date_days_before_now * 2)
    assert T.must(helper.expires_at) > now
    assert helper.trial_enabled?

    # make it expired
    helper.set_number_of_days(actor: User.ghost, days: start_date_days_before_now - 1)

    # check stuff
    assert T.must(helper.expires_at) < now
    assert helper.trial_enabled?
  end
end
