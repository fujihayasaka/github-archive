# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::SeatHistoryTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags

  test "copy_organization_to_owner" do
    history = Copilot::SeatHistory.new
    history.business = create(:business)
    history.billing_cycle_end_date = Date.today
    history.billing_cycle_start_date = Date.today
    history.save!

    assert_equal history.business, history.owner

    history = Copilot::SeatHistory.new
    history.organization = create(:organization)
    history.billing_cycle_end_date = Date.today
    history.billing_cycle_start_date = Date.today
    history.save!

    assert_equal history.organization, history.owner
  end

  sig { params(owner: T.any(::Business, ::Organization)).returns(Copilot::SeatHistory) }
  def create_history(owner)
    history = Copilot::SeatHistory.new

    if owner.is_a?(::Business)
      history.business = owner
    else
      history.organization = owner
    end

    history.billing_cycle_end_date = Date.today
    history.billing_cycle_start_date = Date.today
    history.save!

    history
  end
end if GitHub.copilot_enabled?
