# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsApproveSponsorsListingTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @bizdev = create(:biztools_user)
    @site_admin = create(:staff_admin_user)
    @sponsorable = create(:user, :sponsors_auto_approvable)
    @pending_sponsors_listing = @sponsorable.sponsors_listing
  end

  setup do
    GitHub.flipper[:live_sdn_screening].disable
  end

  context ".call" do
    test "biz dev approves sponsors listing which sets its published_at timestamp" do
      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: @pending_sponsors_listing,
        actor: @bizdev,
      )

      assert_equal @pending_sponsors_listing.reload, result.sponsors_listing
      assert_predicate result, :success?
      assert_empty result.errors
      assert_predicate @pending_sponsors_listing, :approved?
      refute_nil @pending_sponsors_listing.published_at
    end

    test "site admin approves sponsors listing which sets its published_at timestamp" do
      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: @pending_sponsors_listing,
        actor: @site_admin,
      )

      assert_equal @pending_sponsors_listing.reload, result.sponsors_listing
      assert_predicate result, :success?
      assert_empty result.errors
      assert_predicate @pending_sponsors_listing, :approved?
      refute_nil @pending_sponsors_listing.published_at
    end

    test "returns success for already accepted listing" do
      listing = create(:sponsors_listing, :approved)

      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: listing,
        actor: @bizdev,
      )

      assert_equal listing.reload, result.sponsors_listing
      assert_predicate result, :success?
      assert_empty result.errors
      assert_predicate listing, :approved?
    end

    test "sends approval email" do
      result = perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        Sponsors::ApproveSponsorsListing.call(
          sponsors_listing: @pending_sponsors_listing,
          actor: @bizdev,
        )
      end
      assert_predicate result, :success?

      mail = ActionMailer::Base.deliveries.last

      assert_equal "Your GitHub Sponsors profile is live", mail.subject
    end

    test "enqueues CreateMatchDisabledSponsorsActivityJob if sponsorable has active sponsorships" do
      user = create(:user, plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
        created_at: 3.months.ago,
      )
      listing = create(:sponsors_listing, :pending_approval,
        :with_w8_or_w9_verified_stripe_account, sponsorable: user)
      create(:sponsorship, sponsor: user)

      assert_enqueued_with(job: ::CreateMatchDisabledSponsorsActivityJob) do
        Sponsors::ApproveSponsorsListing.call(
          sponsors_listing: listing,
          actor: @bizdev,
        )
      end
    end

    test "does not enqueue CreateMatchDisabledSponsorsActivityJob if sponsorable has no active sponsorships" do
      user = create(:user, plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
        created_at: 3.months.ago,
      )
      listing = create(:sponsors_listing, :pending_approval, sponsorable: user)

      assert_no_enqueued_jobs(only: ::CreateMatchDisabledSponsorsActivityJob) do
        Sponsors::ApproveSponsorsListing.call(
          sponsors_listing: listing,
          actor: @bizdev,
        )
      end
    end

    test "allows auto-approving eligible listing" do
      @pending_sponsors_listing.update!(full_description: "hewwo smol bean")
      create(:sponsors_tier, :published, sponsors_listing: @pending_sponsors_listing)

      assert_predicate @pending_sponsors_listing, :auto_approvable?

      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: @pending_sponsors_listing,
        actor: nil,
        automated: true,
      )

      assert_equal @pending_sponsors_listing.reload, result.sponsors_listing
      assert_predicate result, :success?
      assert_empty result.errors
      assert_predicate @pending_sponsors_listing, :approved?
      refute_nil @pending_sponsors_listing.published_at
    end

    test "allows auto-approving eligible listing with SDN screening enabled" do
      GitHub.flipper[:live_sdn_screening].enable

      @pending_sponsors_listing.update!(full_description: "hewwo smol bean")
      create(:sponsors_tier, :published, sponsors_listing: @pending_sponsors_listing)

      assert_predicate @pending_sponsors_listing, :auto_approvable?

      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: @pending_sponsors_listing,
        actor: nil,
        automated: true,
      )

      assert_equal @pending_sponsors_listing.reload, result.sponsors_listing
      assert_predicate result, :success?
      assert_empty result.errors
      assert_predicate @pending_sponsors_listing, :approved?
      refute_nil @pending_sponsors_listing.published_at
    end

    test "instruments hydro event after acceptance" do
      serialized_user = Hydro::EntitySerializer.user(@pending_sponsors_listing.sponsorable)
      serialized_listing = Hydro::EntitySerializer.sponsors_listing(@pending_sponsors_listing)
      serialized_listing_stafftools_metadata = Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        @pending_sponsors_listing.stafftools_metadata)

      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: @pending_sponsors_listing,
        actor: @bizdev,
      )
      assert_predicate result, :success?

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        user: serialized_user,
        action: "APPROVED",
        listing: serialized_listing,
        listing_stafftools_metadata: serialized_listing_stafftools_metadata,
        automated: false,
      }

      assert_hydro_published(message, schema: "github.sponsors.v0.AccountStatusChange")
    end

    test "instruments audit log event when the listing is approved" do
      events = subscribe "sponsors.sponsored_developer_approve"

      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: @pending_sponsors_listing,
        actor: @bizdev,
      )
      assert_predicate result, :success?

      expected_payload = {
        user: @pending_sponsors_listing.sponsorable_login,
        user_id: @pending_sponsors_listing.sponsorable_id,
        automated: false,
        staff_actor: @bizdev.login,
        staff_actor_id: @bizdev.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        state: :pending_approval,
        short_description: @pending_sponsors_listing.short_description,
        sponsors_listing: @pending_sponsors_listing.slug,
        sponsors_listing_id: @pending_sponsors_listing.id,
        created_by: @pending_sponsors_listing.created_by.login,
        created_by_id: @pending_sponsors_listing.created_by_id,
      }
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments audit log event for automated approval" do
      events = subscribe "sponsors.sponsored_developer_approve"

      @pending_sponsors_listing.update!(full_description: "hewwo smol bean")
      create(:sponsors_tier, :published, sponsors_listing: @pending_sponsors_listing)
      assert_predicate @pending_sponsors_listing, :auto_approvable?

      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: @pending_sponsors_listing,
        actor: nil,
        automated: true,
      )
      assert_predicate result, :success?

      expected_payload = {
        user: @pending_sponsors_listing.sponsorable_login,
        user_id: @pending_sponsors_listing.sponsorable.id,
        automated: true,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        state: :pending_approval,
        short_description: @pending_sponsors_listing.short_description,
        sponsors_listing: @pending_sponsors_listing.slug,
        sponsors_listing_id: @pending_sponsors_listing.id,
        created_by: @pending_sponsors_listing.created_by.login,
        created_by_id: @pending_sponsors_listing.created_by_id,
      }
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments Hydro event after automated approval" do
      serialized_user = Hydro::EntitySerializer.user(@pending_sponsors_listing.sponsorable)
      serialized_listing = Hydro::EntitySerializer.sponsors_listing(@pending_sponsors_listing)
      serialized_listing_stafftools_metadata = Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        @pending_sponsors_listing.stafftools_metadata)

      @pending_sponsors_listing.update!(full_description: "hewwo smol bean")
      assert_predicate @pending_sponsors_listing, :auto_approvable?

      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: @pending_sponsors_listing,
        actor: nil,
        automated: true,
      )
      assert_predicate result, :success?

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        user: serialized_user,
        action: "APPROVED",
        listing: serialized_listing,
        listing_stafftools_metadata: serialized_listing_stafftools_metadata,
        automated: true,
      }

      assert_hydro_published(message, schema: "github.sponsors.v0.AccountStatusChange")
    end

    test "instruments audit log event for automated approval with SDN screening enabled" do
      GitHub.flipper[:live_sdn_screening].enable

      events = subscribe "sponsors.sponsored_developer_approve"

      @pending_sponsors_listing.update!(full_description: "hewwo smol bean")
      create(:sponsors_tier, :published, sponsors_listing: @pending_sponsors_listing)
      assert_predicate @pending_sponsors_listing, :auto_approvable?

      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: @pending_sponsors_listing,
        actor: nil,
        automated: true,
      )
      assert_predicate result, :success?

      expected_payload = {
        user: @pending_sponsors_listing.sponsorable_login,
        user_id: @pending_sponsors_listing.sponsorable.id,
        automated: true,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        state: :pending_approval,
        short_description: @pending_sponsors_listing.short_description,
        sponsors_listing: @pending_sponsors_listing.slug,
        sponsors_listing_id: @pending_sponsors_listing.id,
        created_by: @pending_sponsors_listing.created_by.login,
        created_by_id: @pending_sponsors_listing.created_by_id,
      }
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "returns error for non auto-acceptable listing" do
      listing = @pending_sponsors_listing
      # change the account age to make it approvable...but not auto-approvable
      listing.sponsorable.update!(created_at: Time.now)

      assert_predicate listing, :ready_for_approval?
      refute_predicate listing, :auto_approvable?

      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: listing,
        actor: nil,
        automated: true,
      )

      error_message = "Listing is not auto approvable."
      assert_equal listing.reload, result.sponsors_listing
      refute_predicate result, :success?
      assert_equal [error_message], result.errors
      refute_predicate listing, :approved?
    end

    test "returns error when sponsorable tries to approve listing" do
      sponsorable = @pending_sponsors_listing.sponsorable

      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: @pending_sponsors_listing,
        actor: sponsorable,
      )

      error_message = "#{sponsorable.login} does not have permission to approve the listing."
      assert_equal @pending_sponsors_listing.reload, result.sponsors_listing
      refute_predicate result, :success?
      assert_equal [error_message], result.errors
      refute_predicate @pending_sponsors_listing, :approved?
    end

    test "returns error when listing is not ready for approval" do
      listing = create(:sponsors_listing, :pending_approval, :with_w8_or_w9_requested_but_unverified_stripe_account)

      refute_predicate listing, :ready_for_approval?

      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: listing,
        actor: @bizdev,
      )

      error_message = "Listing is not ready for approval."
      assert_equal listing.reload, result.sponsors_listing
      refute_predicate result, :success?
      assert_equal [error_message], result.errors
    end

    test "returns error when listing cannot be approved" do
      sponsors_listing = create(:sponsors_listing)

      result = Sponsors::ApproveSponsorsListing.call(
        sponsors_listing: sponsors_listing,
        actor: @bizdev,
      )

      error_message = "Listing is not ready for approval."
      assert_equal sponsors_listing.reload, result.sponsors_listing
      refute_predicate result, :success?
      assert_equal [error_message], result.errors
    end
  end
end if GitHub.sponsors_enabled?
