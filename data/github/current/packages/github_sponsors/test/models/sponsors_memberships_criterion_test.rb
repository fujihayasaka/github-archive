# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsMembershipsCriterionTest < GitHub::TestCase
  setup do
    skip unless GitHub.sponsors_enabled?
  end

  fixtures do
    @criterion = create(:sponsors_criterion)
    @listing = create(:sponsors_listing)
  end

  context "validations" do
    test "creates a new membership criterion record" do
      criterion = create(:sponsors_criterion)
      membership_criterion = SponsorsMembershipsCriterion.new(
        sponsors_criterion: criterion,
        sponsors_listing: @listing,
        met: true,
      )

      assert_predicate membership_criterion, :valid?
    end

    test "requires criterion" do
      membership_criterion = SponsorsMembershipsCriterion.new(
        sponsors_criterion: nil,
        sponsors_listing: @listing,
        met: true,
      )

      refute_predicate membership_criterion, :valid?
      assert_equal "Sponsors criterion must exist", membership_criterion.errors.full_messages.to_sentence
    end

    test "requires listing" do
      membership_criterion = SponsorsMembershipsCriterion.new(
        sponsors_criterion: @criterion,
        sponsors_listing: nil,
        met: false,
      )

      refute_predicate membership_criterion, :valid?
      assert_equal "Sponsors listing must exist",
        membership_criterion.errors.full_messages.to_sentence
    end

    test "listing can only have one record per criteria" do
      criterion = create(:sponsors_criterion)
      listing = create(:sponsors_listing)
      existing_member_criterion = listing.sponsors_memberships_criteria.first
      refute_nil existing_member_criterion

      membership_criterion = SponsorsMembershipsCriterion.new(
        sponsors_criterion: existing_member_criterion.sponsors_criterion,
        sponsors_listing: listing,
        met: false,
      )

      refute_predicate membership_criterion, :valid?
      assert_equal "Sponsors criterion has already been taken for Sponsors listing",
        membership_criterion.errors.full_messages.to_sentence
    end
  end

  context "create" do
    test "instruments sponsors_memberships_criterion.create" do
      events = subscribe "sponsors_memberships_criterion.create"

      criterion = create(:sponsors_memberships_criterion, sponsors_listing: @listing)

      expected_payload = {
        sponsors_memberships_criterion_id: criterion.id,
        sponsors_criterion: criterion.sponsors_criterion.slug,
        sponsors_criterion_id: criterion.sponsors_criterion.id,
        met: false,
        criterion_value: nil,
        actor: nil,
        sponsors_listing_id: @listing.id,
        sponsors_listing: @listing.slug,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "update" do
    test "instruments sponsors_memberships_criterion.update" do
      events = subscribe "sponsors_memberships_criterion.update"

      reviewer = create(:biztools_user)
      criterion = create(:sponsors_memberships_criterion, sponsors_listing: @listing)

      criterion.met = true
      criterion.value = "abc123"
      criterion.reviewer = reviewer
      criterion.save!

      expected_payload = {
        sponsors_memberships_criterion_id: criterion.id,
        sponsors_criterion: criterion.sponsors_criterion.slug,
        sponsors_criterion_id: criterion.sponsors_criterion.id,
        met: true,
        criterion_value: "abc123",
        old_met: false,
        old_criterion_value: nil,
        actor: reviewer.login,
        actor_id: reviewer.id,
        sponsors_listing_id: @listing.id,
        sponsors_listing: @listing.slug,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end
end
