# typed: true
# frozen_string_literal: true

require "test_helper"

class UserSuspensionDependencyTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @staffer = create(:staff_admin_user, :staff)
  end

  if GitHub.billing_enabled?
    context "#suspend" do
      test "locks billing when an account is suspended" do
        @user.suspend("Fraudulent account")
        assert_predicate @user, :disabled?
      end

      test "suspending users who already have locked billing" do
        @user.disable!
        @user.suspend("Fraudulent account")
        assert_predicate @user, :disabled?
      end

      test "suspending a user cancels all of their external subscriptions" do
        create(:billing_plan_subscription, :zuora, user: @user)

        assert_enqueued_jobs(1, only: CloseOutZuoraSubscriptionJob) do
          @user.suspend("Fraudulent account")
        end
      end

      test "unsuspending a user recreates all of their external subscriptions" do
        create(:billing_plan_subscription, :zuora, user: @user)
        @user.suspend("Fraudulent account")

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          @user.unsuspend("Not a fraudulent account")
        end
      end

      test "unsuspending a user after suspension should return former locked billing state" do
        @user.disable!
        @user.suspend("Fraudulent account")
        @user.unsuspend("Not a fraudulent account")
        assert_predicate @user, :disabled?
      end

      test "unsuspending a user after suspension should return former unlocked billing state" do
        @user.suspend("Fraudulent account")
        @user.unsuspend("Not a fraudulent account")
        refute_predicate @user, :disabled?
      end

      test "suspending a user does not cancel their iAP subscription" do
        copilot_product_uuid = create(:billing_product_uuid, :copilot)

        listing_plan = create(:marketplace_listing_plan, :published)
        plan_subscription = create(:billing_plan_subscription, :zuora, user: @user)

        non_iap_sub = create(:billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_subscription)
        iap_sub = create(:billing_subscription_item, :iap, subscribable: copilot_product_uuid, plan_subscription: plan_subscription)

        refute_predicate @user, :suspended?
        assert_predicate non_iap_sub, :active?
        assert_predicate iap_sub, :active?

        perform_enqueued_jobs only: [Billing::CancelSubscriptionItemsJob] do
          @user.suspend("Fraudulent account")
        end

        assert_predicate @user.reload, :suspended?
        refute_predicate non_iap_sub.reload, :active?
        assert_predicate iap_sub.reload, :active?
      end

      test "publishes ModerationAction event when user is suspended" do
        @user.suspend(
          "SCOPE_OF_PLATFORM_SERVICES",
          actor: @staffer,
          dsa_source: :USER_REPORT,
          content_creation_date: DateTime.parse("2024-01-01"),
          content_formats: ["TEXT"],
          notes: "test"
        )
        assert_hydro_published({
          action: "user.suspend",
          actor: Hydro::EntitySerializer.user(@staffer),
          account_moderation: {
            account: Hydro::EntitySerializer.user(@user),
            moderation_type: :SUSPENDED,
            end_timestamp: nil
          },
          content_moderation: {
            content_created_at: DateTime.parse("2024-01-01"),
            formats: ["TEXT"]
          },
          countries: nil,
          reason: nil,
          tos_reason: :SCOPE_OF_PLATFORM_SERVICES,
          source: :USER_REPORT,
          is_test: false
        }, schema: "github.moderation.v0.ModerationAction")
      end

      test "publishes ModerationAction event when user is suspended along with other owners" do
        @user.suspend(
          "SCOPE_OF_PLATFORM_SERVICES - flagged with owner",
          actor: @staffer,
          dsa_source: :USER_REPORT,
          content_creation_date: DateTime.parse("2024-01-01"),
          content_formats: ["TEXT"],
          notes: "test"
        )
        assert_hydro_published({
          action: "user.suspend",
          actor: Hydro::EntitySerializer.user(@staffer),
          account_moderation: {
            account: Hydro::EntitySerializer.user(@user),
            moderation_type: :SUSPENDED,
            end_timestamp: nil
          },
          content_moderation: {
            content_created_at: DateTime.parse("2024-01-01"),
            formats: ["TEXT"]
          },
          countries: nil,
          reason: nil,
          tos_reason: :SCOPE_OF_PLATFORM_SERVICES,
          source: :USER_REPORT,
          is_test: false
        }, schema: "github.moderation.v0.ModerationAction")
      end

      test "publishes ModerationAction event when a test user is suspended" do
        @staffer.update!(email: "mona@github.com")
        test_user = create(:user, email: "mona+evil@github.com")
        test_user.suspend(
          "SCOPE_OF_PLATFORM_SERVICES",
          actor: @staffer,
          dsa_source: :USER_REPORT,
          content_creation_date: DateTime.parse("2024-01-01"),
          content_formats: ["TEXT"],
          notes: "test"
        )
        assert_hydro_published({
          action: "user.suspend",
          actor: Hydro::EntitySerializer.user(@staffer),
          account_moderation: {
            account: Hydro::EntitySerializer.user(test_user),
            moderation_type: :SUSPENDED,
            end_timestamp: nil
          },
          content_moderation: {
            content_created_at: DateTime.parse("2024-01-01"),
            formats: ["TEXT"]
          },
          countries: nil,
          tos_reason: :SCOPE_OF_PLATFORM_SERVICES,
          source: :USER_REPORT,
          is_test: true
        }, schema: "github.moderation.v0.ModerationAction")
      end
    end
  end

  if GitHub.sponsors_enabled?
    context "#suspend" do
      test "marks Sponsors profile as spammy" do
        listing = create(:sponsors_listing, :approved)
        sponsorable = listing.sponsorable

        assert_predicate listing, :approved?

        perform_enqueued_jobs(only: DelistSpammySponsorsListingJob) do
          sponsorable.suspend("Suspended!")
        end

        assert_predicate sponsorable.reload, :suspended?
        assert_predicate listing.reload, :spammy?
      end
    end

    context "#unsuspend" do
      test "re-lists Sponsors profile as approved" do
        listing = create(:sponsors_listing, :approved)
        listing.mark_spammy!
        sponsorable = listing.sponsorable
        sponsorable.suspend("Suspended!")

        assert_predicate sponsorable, :suspended?
        assert_predicate listing, :spammy?

        perform_enqueued_jobs(only: RelistNonSpammySponsorsListingJob) do
          sponsorable.unsuspend("Unsuspended!")
        end

        refute_predicate sponsorable.reload, :suspended?
        assert_predicate listing.reload, :approved?
      end
    end
  end
end
