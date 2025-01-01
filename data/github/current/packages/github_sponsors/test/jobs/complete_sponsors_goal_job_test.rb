# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CompleteSponsorsGoalJobTest < GitHub::TestCase
  include JobTestHelper

  if GitHub.sponsors_enabled?
    fixtures do
      @sponsorable = create(:user, :sponsorable)
      @goal = create(:sponsors_goal, listing: @sponsorable.sponsors_listing)

      @sponsor = create(:credit_card_user, :sponsorable,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
      )
    end

    test "retry conditions" do
      assert_retry_on_dirty_exit job: CompleteSponsorsGoalJob, args: [@goal]
    end

    context "#perform" do
      test "marks the goal as completed" do
        assert_predicate @goal, :active?
        assert_predicate @goal.contributions.count, :zero?
        SponsorsPrimerMailer.expects(:goal_completed).with(goal: @goal).once.returns(stub(deliver_later: nil))

        create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)

        CompleteSponsorsGoalJob.perform_now(@goal)

        assert_predicate @goal.reload, :completed?
        assert_equal 1, @goal.contributions.count
      end

      test "creates all the applicable goal contributions" do
        @goal.update!(target_value: 2)

        assert_predicate @goal, :active?
        assert_predicate @goal.contributions.count, :zero?

        create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)
        inactive_sponsor = create(:sponsorship, :inactive, sponsorable: @sponsorable).sponsor
        other_sponsor = create(:sponsorship, sponsorable: @sponsorable).sponsor
        SponsorsPrimerMailer.expects(:goal_completed).with(goal: @goal).once.returns(stub(deliver_later: nil))

        CompleteSponsorsGoalJob.perform_now(@goal)

        assert_predicate @goal.reload, :completed?
        assert_equal 2, @goal.contributions.count

        sponsor_ids = @goal.contributions.pluck(:sponsor_id)
        assert_includes sponsor_ids, @sponsor.id
        assert_includes sponsor_ids, other_sponsor.id
        refute_includes sponsor_ids, inactive_sponsor.id
      end

      test "does nothing if goal has not been achieved yet" do
        assert_predicate @goal, :active?
        refute_predicate @goal, :can_complete?
        assert_predicate @goal.contributions.count, :zero?
        SponsorsPrimerMailer.expects(:goal_completed).never

        CompleteSponsorsGoalJob.perform_now(@goal)

        refute_predicate @goal.reload, :completed?
        assert_predicate @goal.contributions.count, :zero?
      end

      test "does nothing if goal has already been completed" do
        create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)
        @goal.complete!

        assert_predicate @goal.reload, :completed?
        SponsorsPrimerMailer.expects(:goal_completed).never

        assert_no_difference -> { SponsorsGoalContribution.count } do
          CompleteSponsorsGoalJob.perform_now(@goal)
        end

        assert_predicate @goal.reload, :completed?
      end

      test "does not send mailer if sponsorable opted out of all emails" do
        email_opt_outs = SponsorsEmailOptOuts.new(bitmask: nil)
        email_opt_outs.opt_out_of(:all)
        @sponsorable.sponsors_listing.update_email_opt_outs(email_opt_outs)

        create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)

        SponsorsPrimerMailer.expects(:goal_completed).never

        CompleteSponsorsGoalJob.perform_now(@goal)

        assert_predicate @goal.reload, :completed?
      end

      test "does not send mailer if sponsorable opted out of goal completed emails" do
        email_opt_outs = SponsorsEmailOptOuts.new(bitmask: nil)
        email_opt_outs.opt_out_of(:goal_completed)
        @sponsorable.sponsors_listing.update_email_opt_outs(email_opt_outs)

        create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)

        SponsorsPrimerMailer.expects(:goal_completed).never

        CompleteSponsorsGoalJob.perform_now(@goal)

        assert_predicate @goal.reload, :completed?
      end
    end
  end
end
