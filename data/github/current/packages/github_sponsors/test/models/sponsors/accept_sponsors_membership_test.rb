# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsAcceptSponsorsMembershipTest < GitHub::TestCase
  if GitHub.sponsors_enabled?
    fixtures do
      @staff = create(:staff_admin_user)
      @sponsorable = create(:user, :sponsors_old_enough_to_not_get_auto_banned)
      @listing = create(:sponsors_listing, :waitlisted,
        sponsorable: @sponsorable,
        billing_country: SponsorsListing.auto_acceptable_countries.sample,
      )
    end

    context ".call" do
      test "allows a site admin to accept a waitlisted listing" do
        result = Sponsors::AcceptSponsorsMembership.call(
          sponsorable: @sponsorable,
          actor: @staff,
        )

        assert_predicate result, :success?
        assert_equal @sponsorable, result.sponsorable
        assert_empty result.errors
        assert_predicate @listing.reload, :draft?
      end

      test "allows a nil actor to accept a submitted listing for automated acceptance" do
        # delete criteria to keep things simple for tests
        @listing.sponsors_memberships_criteria.delete_all
        automated_criterion = create(:sponsors_criterion, automated: true)
        create(:sponsors_memberships_criterion,
          sponsors_listing: @listing,
          sponsors_criterion: automated_criterion,
          met: true,
        )
        assert_predicate @listing, :auto_acceptable?

        result = Sponsors::AcceptSponsorsMembership.call(
          sponsorable: @sponsorable,
          actor: nil,
          automated: true,
        )

        assert_predicate result, :success?
        assert_equal @sponsorable, result.sponsorable
        assert_empty result.errors
        assert_predicate @listing.reload, :draft?
      end

      test "returns success for draft listing" do
        listing = create(:sponsors_listing)
        assert_predicate listing, :draft?

        result = Sponsors::AcceptSponsorsMembership.call(
          sponsorable: listing.sponsorable,
          actor: @staff,
        )

        assert_predicate result, :success?
        assert_equal listing.sponsorable, result.sponsorable
        assert_empty result.errors
        assert_predicate listing.reload, :draft?
      end

      test "returns failure for liting that cannot transition to draft" do
        listing = create(:sponsors_listing, :banned)

        result = Sponsors::AcceptSponsorsMembership.call(
          sponsorable: listing.sponsorable,
          actor: @staff,
        )

        refute_predicate result, :success?
        assert_equal listing.sponsorable, result.sponsorable
        assert_equal ["There is no event accept defined for the banned state"], result.errors
        refute_predicate listing.reload, :draft?
      end

      test "returns failure for listing belonging to OFAC flagged user" do
        ofac_user = create(:user, :fully_trade_restricted)
        listing = create(:sponsors_listing, :waitlisted, sponsorable: ofac_user)

        result = Sponsors::AcceptSponsorsMembership.call(
          sponsorable: ofac_user,
          actor: @staff,
        )

        refute_predicate result, :success?
        assert_equal ofac_user, result.sponsorable
        assert_equal ["Trade-restricted users are not eligible for GitHub Sponsors"], result.errors
        refute_predicate listing.reload, :draft?
      end

      test "returns failure for unauthorized actor" do
        result = Sponsors::AcceptSponsorsMembership.call(
          sponsorable: @sponsorable,
          actor: create(:user),
        )

        refute_predicate result, :success?
        assert_equal @sponsorable, result.sponsorable
        assert_equal ["Actor is not authorized to accept this membership"], result.errors
        refute_predicate @listing.reload, :draft?
      end

      test "returns failure if actor is missing for non-automated acceptance" do
        result = Sponsors::AcceptSponsorsMembership.call(
          sponsorable: @sponsorable,
          actor: nil,
        )

        refute_predicate result, :success?
        assert_equal @sponsorable, result.sponsorable
        assert_equal ["Actor is not authorized to accept this membership"], result.errors
        refute_predicate @listing.reload, :draft?
      end

      test "returns failure for listing that is not eligible for automated acceptance" do
        @listing.stafftools_metadata.update!(ignored_at: Time.now)
        refute_predicate @listing.reload, :auto_acceptable?

        result = Sponsors::AcceptSponsorsMembership.call(
          sponsorable: @sponsorable,
          actor: nil,
          automated: true,
        )

        refute_predicate result, :success?
        assert_equal @sponsorable, result.sponsorable
        assert_equal ["Membership is not auto acceptable"], result.errors
        refute_predicate @listing.reload, :draft?
      end

      test "returns failure when given a user that has not requested to join Sponsors" do
        result = Sponsors::AcceptSponsorsMembership.call(
          sponsorable: create(:user),
          actor: @staff,
          automated: true,
        )

        refute_predicate result, :success?
        assert_equal ["Given sponsorable has not joined the Sponsors waitlist"], result.errors
      end

      test "increments dogstat for manual acceptance" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        result = Sponsors::AcceptSponsorsMembership.call(
          sponsorable: @sponsorable,
          actor: @staff,
        )

        assert_predicate result, :success?
        assert_equal @sponsorable, result.sponsorable
        assert_empty result.errors
        assert_predicate @listing.reload, :draft?

        assert_equal 1, GitHub.dogstats.increments(
          "sponsors_membership.accept",
          tags: ["automated:false"],
        ).count
      end

      test "increments dogstat for automatic acceptance" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        # delete criteria to keep things simple for tests
        @listing.sponsors_memberships_criteria.delete_all
        automated_criterion = create(:sponsors_criterion, automated: true)
        create(:sponsors_memberships_criterion,
          sponsors_listing: @listing,
          sponsors_criterion: automated_criterion,
          met: true,
        )

        assert_predicate @listing, :auto_acceptable?

        result = Sponsors::AcceptSponsorsMembership.call(
          sponsorable: @sponsorable,
          actor: nil,
          automated: true,
        )

        assert_predicate result, :success?
        assert_equal @sponsorable, result.sponsorable
        assert_empty result.errors
        assert_predicate @listing.reload, :draft?

        assert_equal 1, GitHub.dogstats.increments(
          "sponsors_membership.accept",
          tags: ["automated:true"],
        ).count
      end

      test "instruments audit log event for manual acceptance" do
        events = subscribe "sponsors_membership.accept"
        expected_payload = {
          automated: false,
          sponsors_listing_id: @listing.id,
          sponsors_listing: @listing.slug,
          short_description: @listing.short_description,
          state: :waitlisted,
          user: @sponsorable.login,
          user_id: @sponsorable.id,
          staff_actor: @staff.login,
          staff_actor_id: @staff.id,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          created_by: @listing.created_by.login,
          created_by_id: @listing.created_by.id,
        }

        Sponsors::AcceptSponsorsMembership.call(
          sponsorable: @sponsorable,
          actor: @staff,
        )

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments audit log event for automated acceptance" do
        events = subscribe "sponsors_membership.accept"
        sponsorable = @listing.sponsorable
        expected_payload = {
          automated: true,
          sponsors_listing_id: @listing.id,
          sponsors_listing: @listing.slug,
          short_description: @listing.short_description,
          state: :waitlisted,
          user: sponsorable.login,
          user_id: sponsorable.id,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          created_by: @listing.created_by.login,
          created_by_id: @listing.created_by.id,
        }

        # delete criteria to keep things simple for tests
        @listing.sponsors_memberships_criteria.delete_all
        automated_criterion = create(:sponsors_criterion, automated: true)
        create(:sponsors_memberships_criterion,
          sponsors_listing: @listing,
          sponsors_criterion: automated_criterion,
          met: true,
        )

        Sponsors::AcceptSponsorsMembership.call(
          sponsorable: @sponsorable,
          actor: nil,
          automated: true,
        )

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments audit log event for organization sponsorable" do
        events = subscribe "sponsors_membership.accept"
        org = create(:organization, :sponsors_old_enough_to_not_get_auto_banned)
        listing = create(:sponsors_listing, :waitlisted, :for_org, sponsorable: org)
        expected_payload = {
          automated: false,
          sponsors_listing_id: listing.id,
          sponsors_listing: listing.slug,
          short_description: listing.short_description,
          state: :waitlisted,
          org: org.login,
          org_id: org.id,
          staff_actor: @staff.login,
          staff_actor_id: @staff.id,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          created_by: listing.created_by.login,
          created_by_id: listing.created_by.id,
        }

        result = Sponsors::AcceptSponsorsMembership.call(
          sponsorable: org,
          actor: @staff,
        )

        assert_empty result.errors
        assert_predicate result, :success?
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end
  end
end
