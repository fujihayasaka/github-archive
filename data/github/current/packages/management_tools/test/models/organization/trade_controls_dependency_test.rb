# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTradeControlsDependencyTest < GitHub::TestCase
  context "#restricted_member_count" do
    test "counts any org member that is not unrestricted" do
      org = create(:organization)
      1.times { org.add_member create(:user) }
      3.times { org.add_member create(:user, :trade_unrestricted) }
      5.times { org.add_member create(:user, :fully_trade_restricted) }

      assert_equal 5, org.trade_controls_restricted_members.count
    end
  end
end
