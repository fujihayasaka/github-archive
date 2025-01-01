# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::BatchUpdateStandaloneUserSettingsJobTest < GitHub::TestCase
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
    test "it will do nothing if the business is not copilot standalone" do
      seat = create(:copilot_seat)
      biz = seat.organization.business

      assert_no_changes -> { enqueued_jobs.count } do
        Copilot::BatchUpdateStandaloneUserSettingsJob.perform_now(biz)
      end
    end

    test "it will work" do
      user = create(:user)
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      T.must(@business).add_user_accounts([user.id], business_roles_bitfield: 0)
      enterprise_team = create(:enterprise_team, business: @business)
      enterprise_team.enterprise_team_memberships.create!(user_id: user.id)

      owner = T.must(@business).owners.first
      assignment = Copilot::SeatAssignment.new(assignable: enterprise_team, owner: @business, assigning_user: owner)
      assignment.save!
      assignment.convert_to_seats
      Copilot::BatchUpdateStandaloneUserSettingsJob.perform_now(T.must(@business))
      job = enqueued_jobs[-1]

      seat = T.must(Copilot::Seat.for_business(T.must(@business)).first)
      assert_equal Copilot::UpdateStandaloneUserSettingsCacheJob, job[:job]
      assert_equal [T.must(@business).id, seat.id, seat.id], job[:args]
    end

    test "it will work with many seats" do
      Copilot::Business.any_instance.stubs(:copilot_billable?).returns(true)
      enterprise_team = create(:enterprise_team, business: @business)
      owner = T.must(@business).owners.first

      (Copilot::BatchUpdateStandaloneUserSettingsJob::BATCH_SIZE + 1).times do
        user = create(:user)
        T.must(@business).add_user_accounts([user.id], business_roles_bitfield: 0)
        enterprise_team.enterprise_team_memberships.create!(user_id: user.id)
      end

      assignment = Copilot::SeatAssignment.new(assignable: enterprise_team, owner: @business, assigning_user: owner)
      assignment.save!
      assignment.convert_to_seats

      seats = Copilot::Seat.for_business(T.must(@business)).to_a
      Copilot::BatchUpdateStandaloneUserSettingsJob.perform_now(T.must(@business))
      # first enqueued
      batch_job_1 = enqueued_jobs[-2]
      # next enqueued
      batch_job_2 = enqueued_jobs[-1]

      assert_equal Copilot::UpdateStandaloneUserSettingsCacheJob, batch_job_1[:job]
      assert_equal [T.must(@business).id, T.must(seats[0]).id, T.must(seats[-2]).id], batch_job_1[:args]
      assert_equal Copilot::UpdateStandaloneUserSettingsCacheJob, batch_job_2[:job]
      assert_equal [T.must(@business).id, T.must(seats[-1]).id, T.must(seats[-1]).id], batch_job_2[:args]

    end
  end
end if GitHub.copilot_enabled?
