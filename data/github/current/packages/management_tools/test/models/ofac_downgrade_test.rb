# typed: true
# frozen_string_literal: true

require "test_helper"

class OFACDowngradeTest < GitHub::TestCase
  context ".schedule_for" do
    test "creates a downgrade record for the user" do
      user = create(:user, :fully_trade_restricted)
      Timecop.freeze do
        downgrade = OFACDowngrade.schedule_for(user)

        assert_equal user.id, downgrade.user_id
        assert_equal GitHub::Billing.today + OFACDowngrade::APPEAL_BUFFER, downgrade.downgrade_on
      end
    end

    test "can't create duplicate incomplete downgrades" do
      user = create(:user, :fully_trade_restricted)
      create(:ofac_downgrade, user_id: user.id)

      downgrade = OFACDowngrade.schedule_for(user)

      refute_predicate downgrade, :valid?
      assert_equal "no duplicate downgrades can be created", downgrade.errors.full_messages.first
    end
  end

  context "#run" do
    test "performs the OFAC Compliance downgrade for the associated user" do
      downgrade = create(:ofac_downgrade)

      ::Billing::OFACCompliance::Downgrade
        .expects(:perform)
        .with(downgrade.user, actor: downgrade.user)
        .once

      downgrade.run

      assert_predicate downgrade, :is_complete?
    end
  end

  context "#past_scheduled_run_date" do
    test "check if downgrade is past scheduled run date" do
      downgrade = create(:ofac_downgrade)
      assert_equal false, downgrade.past_scheduled_run_date?

      Timecop.freeze(downgrade.downgrade_on + 31) do
        assert_equal true, downgrade.past_scheduled_run_date?
      end
    end
  end
end
