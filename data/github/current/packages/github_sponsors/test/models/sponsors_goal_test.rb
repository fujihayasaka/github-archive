# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsGoalTest < GitHub::TestCase
  include HydroTestHelpers

  if GitHub.sponsors_enabled?
    fixtures do
      @sponsorable = create(:user)
      @listing = create(:sponsors_listing, :approved, :with_stripe_account, sponsorable: @sponsorable)
      @one_time_tier = create(:sponsors_tier, :published, :one_time,
        sponsors_listing: @listing, monthly_price_in_cents: 100_00)
      @goal = create(:sponsors_goal, listing: @listing)
      @completed_goal = create(:sponsors_goal, :completed, listing: @listing)
      @retired_goal = create(:sponsors_goal, :retired, listing: @listing)
      @bizdev = create(:biztools_user)
      @draft_listing = create(:sponsors_listing)
      @org_listing = create(:sponsors_listing, :approved, :for_org)
      @org_admin = @org_listing.sponsorable.admins.first
    end

    context "#publicly_visible?" do
      test "true for active goal on an approved listing" do
        assert_predicate @goal, :publicly_visible?
      end

      test "false for active goal on an unapproved listing" do
        goal = build(:sponsors_goal, listing: @draft_listing)
        refute_predicate goal, :publicly_visible?
      end

      test "false for retired goal on an approved listing" do
        refute_predicate @retired_goal, :publicly_visible?
      end

      test "false for completed goal on an approved listing" do
        refute_predicate @completed_goal, :publicly_visible?
      end
    end

    context "#readable_by?" do
      test "true for listing admin for retired goal" do
        assert @retired_goal.readable_by?(@sponsorable)
      end

      test "true for listing admin for completed goal" do
        assert @completed_goal.readable_by?(@sponsorable)
      end

      test "true for listing admin for active goal" do
        assert @goal.readable_by?(@sponsorable)
      end

      test "true for biztools user for retired goal" do
        assert @retired_goal.readable_by?(@bizdev)
      end

      test "true for biztools user for completed goal" do
        assert @completed_goal.readable_by?(@bizdev)
      end

      test "true for biztools user for active goal" do
        assert @goal.readable_by?(@bizdev)
      end

      test "false for rando for retired goal" do
        refute @retired_goal.readable_by?(create(:user))
      end

      test "false for rando for completed goal" do
        refute @completed_goal.readable_by?(create(:user))
      end

      test "true for rando for active goal" do
        assert @goal.readable_by?(create(:user))
      end

      test "false for rando for unpublished listing's goal" do
        goal = create(:sponsors_goal, listing: @draft_listing)
        refute goal.readable_by?(create(:user))
      end

      test "true for biztools user for unpublished listing's goal" do
        goal = create(:sponsors_goal, listing: @draft_listing)
        assert goal.readable_by?(@bizdev)
      end

      test "true for listing admin for unpublished listing's goal" do
        goal = create(:sponsors_goal, listing: @draft_listing)
        assert goal.readable_by?(@draft_listing.sponsorable)
      end

      test "false for rando for org listing's retired goal" do
        goal = create(:sponsors_goal, :retired, listing: @org_listing)
        refute goal.readable_by?(create(:user))
      end

      test "true for org admin for org listing's retired goal" do
        goal = create(:sponsors_goal, :retired, listing: @org_listing)
        assert goal.readable_by?(@org_admin)
      end

      test "false for rando for org listing's completed goal" do
        goal = create(:sponsors_goal, :completed, listing: @org_listing)
        refute goal.readable_by?(create(:user))
      end

      test "true for org admin for org listing's completed goal" do
        goal = create(:sponsors_goal, :completed, listing: @org_listing)
        assert goal.readable_by?(@org_admin)
      end

      test "true for rando for org listing's active goal" do
        goal = create(:sponsors_goal, listing: @org_listing)
        assert goal.readable_by?(create(:user))
      end
    end

    context ".active_goal_for" do
      test "returns nil when given sponsorable's listing has no goals" do
        sponsorable = create(:user, :sponsorable)
        assert_nil SponsorsGoal.active_goal_for(sponsorable_id: sponsorable.id)
      end

      test "returns active goal for specified sponsorable's listing" do
        assert_equal @goal, SponsorsGoal.active_goal_for(sponsorable_id: @sponsorable.id)
      end

      test "returns nil when sponsorable's listing does not have an active goal" do
        @goal.retire!
        assert_nil SponsorsGoal.active_goal_for(sponsorable_id: @sponsorable.id)
      end
    end

    context "#adminable_by?" do
      test "true for Sponsors listing admin" do
        SponsorsListing.any_instance.stubs(:async_adminable_by?).returns(Promise.resolve(true))
        assert @goal.adminable_by?(create(:user))
      end

      test "false for Sponsors listing non-admin" do
        SponsorsListing.any_instance.stubs(:async_adminable_by?).returns(Promise.resolve(false))
        refute @goal.adminable_by?(create(:user))
      end
    end

    context "associations" do
      test "destroys goal contributions when goal is destroyed" do
        create(:sponsors_goal_contribution, goal: @goal)

        assert_equal 1, SponsorsGoalContribution.count
        assert_equal 1, @goal.reload.contributions.count

        assert_difference -> { SponsorsGoalContribution.count }, -1 do
          @goal.destroy
        end
      end
    end

    context "#for_organization?" do
      test "true for a goal for an organization's Sponsors listing" do
        goal = build(:sponsors_goal, listing: @org_listing)
        assert_predicate goal, :for_organization?
      end

      test "false for a goal for an user's Sponsors listing" do
        assert_predicate @goal.sponsorable, :user?, "need a user sponsorable"
        refute_predicate @goal, :for_organization?
      end
    end

    context "validations" do
      test "requires a sponsors listing" do
        @goal.listing = nil

        refute_predicate @goal, :valid?
        assert_includes @goal.errors[:listing], "must exist"
      end

      test "requires target value presence" do
        @goal.target_value = nil

        refute_predicate @goal, :valid?
        assert_includes @goal.errors[:target_value], "is not a number"
      end

      test "validates target value to be greater than 0" do
        @goal.target_value = 0

        refute_predicate @goal, :valid?
        assert_includes @goal.errors[:target_value], "must be greater than 0"
      end

      test "validates target value to be less than max limit" do
        @goal.target_value = SponsorsGoal::MAX_TARGET_VALUE + 1

        refute_predicate @goal, :valid?
        assert_includes @goal.errors[:target_value], "must be less than #{SponsorsGoal::MAX_TARGET_VALUE}"
      end

      test "target value does not raise RangeError" do
        @goal.target_value = SponsorsGoal::MAX_TARGET_VALUE + 1
        refute @goal.save

        @goal.reload
        refute @goal.update(target_value: SponsorsGoal::MAX_TARGET_VALUE + 1)
      end

      test "validates target value to be an integer" do
        @goal.target_value = 1.1

        refute_predicate @goal, :valid?
        assert_includes @goal.errors[:target_value], "must be an integer"
      end

      test "requires description presence" do
        @goal.description = nil

        refute_predicate @goal, :valid?
        assert_includes @goal.errors[:description], "can't be blank"
      end

      test "validates description length" do
        long_description = "a" * (SponsorsGoal::MAX_DESCRIPTION_LENGTH + 1)
        @goal.description = long_description

        refute_predicate @goal, :valid?
        description_err = "is too long (maximum is #{SponsorsGoal::MAX_DESCRIPTION_LENGTH} characters)"
        assert_includes @goal.errors[:description], description_err
      end

      test "validates only one active goal per listing" do
        other_goal = build(:sponsors_goal, :active, listing: @listing.reload)
        another_goal = create(:sponsors_goal, :active)

        assert_predicate @goal, :valid?
        assert_predicate another_goal, :valid?
        refute_predicate other_goal, :valid?
        assert_includes other_goal.errors[:base], "Only one active goal can exist at a time."
      end

      test "cannot set a completed target value if the goal is active" do
        @goal.update(target_value: 2, kind: :total_sponsors_count)
        tier = create(:sponsors_tier, :published, sponsors_listing: @listing)
        create(:sponsorship, tier: tier, sponsorable: @sponsorable)

        assert_predicate @goal.reload, :valid?
        refute_predicate @goal, :can_complete?

        @goal.target_value = 1

        refute_predicate @goal, :valid?
        assert_includes @goal.errors[:base],
          "You already achieved this goal. Way to go! Try setting a different goal target."
      end
    end

    context "state transitions" do
      test "active goals can transition to retired" do
        assert_predicate @goal, :active?
        assert_predicate @goal.retired_at, :blank?

        @goal.retire!

        assert_predicate @goal.reload, :retired?
        assert_predicate @goal.retired_at, :present?
      end

      test "active goals can transition to completed if achieved sponsors count" do
        assert_equal 1, @goal.target_value
        assert_predicate @goal, :total_sponsors_count?
        assert_predicate @goal, :active?
        assert_predicate @goal.completed_at, :blank?

        tier = create(:sponsors_tier, :published, listing: @listing)
        create(:sponsorship, sponsorable: @sponsorable, tier: tier)

        @goal.reload.complete!

        assert_predicate @goal.reload, :completed?
        assert_predicate @goal.completed_at, :present?
      end

      test "active goals can transition to completed if achieved sponsorship amount" do
        @goal.update!(kind: :monthly_sponsorship_amount)

        assert_equal 1, @goal.target_value
        assert_predicate @goal, :monthly_sponsorship_amount?
        assert_predicate @goal, :active?
        assert_predicate @goal.completed_at, :blank?

        tier = create(:sponsors_tier, :published, listing: @listing)
        create(:sponsorship, :with_billing_transaction_and_line_item,
          sponsorable: @sponsorable, tier: tier)

        @goal.reload.complete!

        assert_predicate @goal.reload, :completed?
        assert_predicate @goal.completed_at, :present?
      end

      test "contributions are recorded when a goal transitions to complete" do
        total_contributors = @goal.target_value + 1
        active_sponsorships = create_list(:sponsorship, total_contributors,
          sponsorable: @sponsorable)
        expected_contributors = active_sponsorships.map(&:sponsor)

        # These sponsors shouldn't be contributors because their sponsorships are inactive:
        create_list(:sponsorship, 2, :inactive, sponsorable: @sponsorable)

        # This sponsor shouldn't be a contributor because they made a one-time payment:
        create(:sponsorship, sponsorable: @sponsorable, tier: @one_time_tier)

        # Should not count since invoiced sponsorship:
        transfer = create(:invoiced_sponsorship_transfer, sponsors_listing: @sponsorable.sponsors_listing)
        create(:sponsorship, :invoiced, invoiced_sponsorship_transfer: transfer)

        assert_predicate @goal.contributions, :empty?

        assert_difference -> { SponsorsGoalContribution.count }, total_contributors do
          @goal.complete!
        end

        assert_same_elements expected_contributors, @goal.reload.contributions.map(&:sponsor)
      end

      test "instruments hydro event when a goal transtions to complete" do
        tier = create(:sponsors_tier, :published, listing: @listing)
        create(:sponsorship, sponsorable: @sponsorable, tier: tier)

        @goal.reload.complete!

        assert_hydro_messages(count: 1, schema: "github.sponsors.v1.GoalEvent")
        assert_hydro_published({
          listing: Hydro::EntitySerializer.sponsors_listing(@listing),
          goal: Hydro::EntitySerializer.sponsors_goal(@goal).merge(state: :ACTIVE),
          action: :COMPLETED,
          sponsorable: Hydro::EntitySerializer.user(@sponsorable),
        }, schema: "github.sponsors.v1.GoalEvent")
      end

      test "retires a goal when no contributions are present" do
        inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: @sponsorable)

        assert_predicate @goal.contributions, :empty?

        @goal.retire!

        assert_predicate @goal.reload.contributions, :empty?
      end

      test "contributions are recorded when a goal transitions to retired" do
        active_sponsorship = create(:sponsorship, sponsorable: @sponsorable)
        inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: @sponsorable)

        @goal.update!(target_value: 42)

        assert_predicate @goal.contributions, :empty?

        @goal.retire!

        actual_contributors = @goal.reload.contributions.pluck(:sponsor_id)
        assert_same_elements [active_sponsorship.sponsor_id], actual_contributors
      end
    end

    context "#title" do
      test "uses correct title for monthly sponsorship goals" do
        @goal.update(kind: :monthly_sponsorship_amount)
        assert_equal "$1 per month", @goal.title
      end

      test "uses correct title for number of sponsors goals" do
        @goal.update(kind: :total_sponsors_count)
        assert_equal "1 monthly sponsor", @goal.title
      end
    end

    context "#current_value" do
      test "returns total active recurring sponsorships when kind is total sponsors" do
        tier = create(:sponsors_tier, :published, sponsors_listing: @listing)

        create(:sponsorship, tier: tier, sponsorable: @sponsorable)

        # Should not count since inactive:
        create(:sponsorship, :inactive, tier: tier, sponsorable: @sponsorable)

        # Should not count since one-time tier:
        create(:sponsorship, tier: @one_time_tier, sponsorable: @sponsorable)

        # Should not count since invoiced sponsorship:
        transfer = create(:invoiced_sponsorship_transfer, sponsors_listing: @sponsorable.sponsors_listing)
        create(:sponsorship, :invoiced, invoiced_sponsorship_transfer: transfer)

        assert_equal 1, @goal.reload.current_value
      end

      test "returns dollar amount received in past 30 days from recurring sponsorships, excluding prorated payments, when kind is monthly sponsorship amount" do
        goal = create(:sponsors_goal, :monthly_sponsorship_amount, tier_count: 0,
          target_value: 125) # $125.00 goal
        listing = goal.listing
        tier = create(:sponsors_tier, :published, sponsors_listing: listing,
          monthly_price_in_cents: 5000)
        one_time_tier = create(:sponsors_tier, :published, :one_time,
          sponsors_listing: goal.listing, monthly_price_in_cents: 100_00)


        # $50.00 + $50.00 = $100.00
        create(:sponsorship, :with_billing_transaction_and_line_item, sponsorable: listing.sponsorable, tier: tier)
        create(:sponsorship, :with_billing_transaction_and_line_item, sponsorable: listing.sponsorable, tier: tier)

        # Shouldn't count toward goal since one-time tier:
        create(:sponsorship, :with_billing_transaction_and_line_item, sponsorable: listing.sponsorable, tier: one_time_tier)

        # Shouldn't count toward goal since inactive:
        create(:sponsorship, :with_billing_transaction_and_line_item, :inactive, sponsorable: listing.sponsorable, tier: tier)

        # Shouldn't count toward goal since prorated:
        create(:sponsorship, :with_prorated_billing_transaction_and_line_item, sponsorable: listing.sponsorable, tier: tier)

        # Should not count since invoiced sponsorship:
        transfer = create(:invoiced_sponsorship_transfer, sponsors_listing: listing)
        create(:sponsorship, :invoiced, invoiced_sponsorship_transfer: transfer)

        assert_equal 100, goal.current_value
      end
    end

    context "percent_complete" do
      test "returns percentage based on target value" do
        tier = create(:sponsors_tier, :published, sponsors_listing: @listing)
        create(:sponsorship, tier: tier, sponsorable: @sponsorable)

        assert_equal 1, @goal.target_value
        assert_equal 100, @goal.percent_complete
      end

      test "returns zero when target value is invalid" do
        goal = build(:sponsors_goal, target_value: :INVALID)
        assert_equal 0, goal.percent_complete
      end
    end

    context "#near_complete?" do
      test "returns true when the goal completion percentage is at or past the threshold" do
        @goal.update!(target_value: 10, kind: :monthly_sponsorship_amount)
        tier = create(:sponsors_tier, :published,
          sponsors_listing: @listing, monthly_price_in_cents: 8_00)

        create(:sponsorship, :with_billing_transaction_and_line_item, tier: tier, sponsorable: @sponsorable)

        assert_equal 10, @goal.target_value
        assert_equal 80, @goal.percent_complete
        assert_predicate @goal, :near_complete?
      end

      test "returns false when the goal completion percentage is below the threshold" do
        @goal.update!(target_value: 10, kind: :monthly_sponsorship_amount)
        tier = create(:sponsors_tier, :published,
          sponsors_listing: @listing, monthly_price_in_cents: 7_00)

        create(:sponsorship, :with_billing_transaction_and_line_item, tier: tier, sponsorable: @sponsorable)

        assert_equal 10, @goal.target_value
        assert_equal 70, @goal.percent_complete
        refute_predicate @goal, :near_complete?
      end

      test "returns false when the goal is complete" do
        @goal.update!(target_value: 10, kind: :monthly_sponsorship_amount)
        tier = create(:sponsors_tier, :published,
          sponsors_listing: @listing, monthly_price_in_cents: 10_00)

        create(:sponsorship, :with_billing_transaction_and_line_item, tier: tier, sponsorable: @sponsorable)

        assert_equal 10, @goal.target_value
        assert_equal 100, @goal.percent_complete
        refute_predicate @goal, :near_complete?
      end
    end

    context "#instrument_near_complete_event" do
      test "triggers a near complete goal event" do
        @goal.instrument_near_complete_event

        assert_hydro_messages(count: 1, schema: "github.sponsors.v1.GoalEvent")
        assert_hydro_published({
          listing: Hydro::EntitySerializer.sponsors_listing(@listing),
          goal: Hydro::EntitySerializer.sponsors_goal(@goal),
          action: :NEAR_COMPLETED,
          sponsorable: Hydro::EntitySerializer.user(@sponsorable),
        }, schema: "github.sponsors.v1.GoalEvent")
      end

      test "only triggers the event once" do
        @goal.instrument_near_complete_event
        @goal.instrument_near_complete_event
        @goal.instrument_near_complete_event

        assert_hydro_messages(count: 1, schema: "github.sponsors.v1.GoalEvent")
      end

      test "triggers the event again after 1 month" do
        @goal.instrument_near_complete_event

        travel_to 2.months.from_now do
          @goal.instrument_near_complete_event
        end

        assert_hydro_messages(count: 2, schema: "github.sponsors.v1.GoalEvent")
      end
    end

    context "target_for_conditional_access" do
      test "tfca defers to sponsors listing" do
        assert_equal @goal.listing.target_for_conditional_access, @goal.target_for_conditional_access
      end

      test "async_tfca defers to sponsors listing" do
        assert_equal @goal.listing.target_for_conditional_access, @goal.async_target_for_conditional_access.sync
      end
    end
  end
end
