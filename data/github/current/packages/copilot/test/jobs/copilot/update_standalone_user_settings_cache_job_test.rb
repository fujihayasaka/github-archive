# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::UpdateStandaloneUserSettingsCacheJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @business = T.let(create(:business, :enterprise_managed_business, seats_plan_type: :basic), T.nilable(Business))

    if TestEnv.test_with_all_emus?
      unless @business.nil?
        @business.update(seats_plan_type: "basic")
        provider = create(:business_saml_provider, business: @business)
        create(:external_identity, provider: provider, user: @business.owners.first)
      end

      create(:billing_sales_serve_plan_subscription, customer: T.must(@business).customer)
    end
  end

  setup do
    Copilot::Business.new(T.must(@business)).enable_copilot!
  end

  context "perform" do
    test "it will work" do
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      enterprise_team = create(:enterprise_team, business: @business)
      owner = T.must(@business).owners.first

      3.times do
        user = create(:user)
        T.must(@business).add_user_accounts([user.id], business_roles_bitfield: 0)
        enterprise_team.enterprise_team_memberships.create!(user_id: user.id)
      end

      assignment = Copilot::SeatAssignment.new(assignable: enterprise_team, owner: @business, assigning_user: owner)
      assignment.save!
      assignment.convert_to_seats

      seats = Copilot::Seat.for_business(T.must(@business)).to_a
      mock = Minitest::Mock.new
      3.times { mock.expect(:create_copilot_settings_cache, true, [Copilot::Public::User::CURRENT_VERSION]) }
      Copilot::User.expects(:new).with(T.must(seats[0]).assigned_user).returns(mock)
      Copilot::User.expects(:new).with(T.must(seats[1]).assigned_user).returns(mock)
      Copilot::User.expects(:new).with(T.must(seats[2]).assigned_user).returns(mock)

      Copilot::UpdateStandaloneUserSettingsCacheJob.perform_now(
        T.must(T.must(@business).id),
        T.must(seats[0]).id,
        T.must(seats[2]).id
      )
    end
  end
end if GitHub.copilot_enabled?
