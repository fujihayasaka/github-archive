# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsorship::StateDependencyTest < GitHub::TestCase

  fixtures do
    @pending_sponsorship = create(:sponsorship, :pending)
    @active_sponsorship = create(:sponsorship)
    @inactive_sponsorship = create(:sponsorship, :inactive)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  context "state transitions" do
    test "sponsorship can transition from pending to active" do
      @pending_sponsorship.payment_completed!

      assert_predicate @pending_sponsorship, :active_test?
    end
  end
end
