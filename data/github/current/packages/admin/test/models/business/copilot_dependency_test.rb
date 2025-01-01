# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessCopilotTest < GitHub::TestCase
  test "defaults to COPILOT_ENTERPRISE_TEAM_MAX_SEATS_DEFAULT if not persisted" do
    business = build(:business)
    assert_equal Copilot::COPILOT_ENTERPRISE_TEAM_MAX_SEATS_DEFAULT, business.copilot_max_seats
  end

  test "noop setter if business is not persisted" do
    business = build(:business)
    business.copilot_max_seats = 1999
    assert_equal Copilot::COPILOT_ENTERPRISE_TEAM_MAX_SEATS_DEFAULT, business.copilot_max_seats
  end

  test "stores value in Copilot::Configuration if business is persisted" do
    business = create(:business)
    assert_equal Copilot::COPILOT_ENTERPRISE_TEAM_MAX_SEATS_DEFAULT, business.copilot_max_seats
    business.copilot_max_seats = 1999
    business.save!
    assert_equal 1999, business.copilot_max_seats

    configuration = Copilot::Configuration.find_by(configurable: business)
    assert_equal 1999, T.must(configuration).max_seats
  end
end
