# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsPatreonUserTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @spu = create(:sponsors_patreon_user)
    @patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: @spu)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
    @fake_receiving_url = "https://www.github.localhost.com/sponsors/patreon_webhook"
  end

  context "#refresh_tokens_or_destroy" do
    test "no-op when there is no refresh token" do
      @spu.update!(patreon_refresh_token: nil)

      assert_no_enqueued_jobs(only: RefreshSponsorsPatreonTokensJob) do
        refute @spu.refresh_tokens_or_destroy
      end

      assert SponsorsPatreonUser.exists?(@spu.id)
    end

    test "deletes the Patreon user when refreshing token fails due to lack of authorization" do
      SponsorsPatreonClient.expects(:refresh_token).once.with(@spu.patreon_refresh_token)
        .raises(SponsorsPatreonClient::UnauthorizedError.new)
      SponsorsPatreonClient.any_instance.expects(:get_webhooks).once
        .raises(SponsorsPatreonClient::UnauthorizedError.new)

      assert_no_enqueued_jobs(only: RefreshSponsorsPatreonTokensJob) do
        refute @spu.refresh_tokens_or_destroy
      end

      refute SponsorsPatreonUser.exists?(@spu.id)
    end

    test "updates the Patreon user with new tokens when the refresh attempt succeeds" do
      @spu.update!(patreon_access_token: "expired_token", patreon_refresh_token: "my_refresh_token")
      expires_in = 2678400 # see VCR cassette
      freeze_time
      expected_enqueue_time = Time.now + expires_in.seconds -
        SponsorsPatreonUser::TOKEN_EXPIRY_GRACE_PERIOD_IN_DAYS.days

      assert_enqueued_with(
        job: RefreshSponsorsPatreonTokensJob,
        at: expected_enqueue_time,
        args: [@spu],
      ) do
        VCR.use_cassette("patreon/refresh_token") do
          assert @spu.refresh_tokens_or_destroy
        end
      end

      assert_equal "lovely-new-access-token", @spu.reload.patreon_access_token # see VCR cassette
      assert_equal "fancy-new-refresh-token", @spu.patreon_refresh_token # see VCR cassette
    end

    test "deletes the Patreon user when the refresh attempt doesn't return new tokens" do
      SponsorsPatreonClient.expects(:refresh_token).once.with(@spu.patreon_refresh_token)
        .returns({ "your_tokens" => "are in another castle" })
      SponsorsPatreonClient.any_instance.expects(:get_webhooks).once
        .raises(SponsorsPatreonClient::UnauthorizedError.new)

      assert_no_enqueued_jobs(only: RefreshSponsorsPatreonTokensJob) do
        refute @spu.refresh_tokens_or_destroy
      end

      refute SponsorsPatreonUser.exists?(@spu.id)
    end

    # https://github.com/github/sponsors/issues/5419
    test "deletes the Patreon user when the associated user no longer exists" do
      @spu.user.delete
      SponsorsPatreonClient.expects(:refresh_token).never
      SponsorsPatreonClient.any_instance.expects(:get_webhooks).once
        .raises(SponsorsPatreonClient::UnauthorizedError.new)

      assert_no_enqueued_jobs(only: RefreshSponsorsPatreonTokensJob) do
        refute @spu.reload.refresh_tokens_or_destroy
      end

      refute SponsorsPatreonUser.exists?(@spu.id)
    end
  end

  context "#approved_sponsors_listing?" do
    if GitHub.sponsors_enabled?
      test "returns true when the associated SponsorsListing is approved" do
        listing = create(:sponsors_listing, :approved)
        spu = create(:sponsors_patreon_user, user: listing.sponsorable)

        assert_predicate spu, :approved_sponsors_listing?
      end
    else
      test "returns false when Sponsors is not a feature" do
        listing = create(:sponsors_listing, :approved)
        spu = create(:sponsors_patreon_user, user: listing.sponsorable)

        refute_predicate spu, :approved_sponsors_listing?
      end
    end

    test "returns false when the associated SponsorsListing is not approved" do
      listing = create(:sponsors_listing, :draft)
      spu = create(:sponsors_patreon_user, user: listing.sponsorable)

      refute_predicate spu, :approved_sponsors_listing?
    end

    test "returns false when there is no associated SponsorsListing" do
      spu = create(:sponsors_patreon_user, :sponsor)
      assert_nil spu.sponsors_listing, "need a SponsorsPatreonUser without a SponsorsListing"

      refute_predicate spu, :approved_sponsors_listing?
    end
  end

  context ".for_patreon_campaign scope" do
    test "returns Patreon users who own the Patreon webhook with the given campaign ID" do
      webhook1, webhook2 = create_pair(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: @spu)

      assert_equal [@spu], SponsorsPatreonUser.for_patreon_campaign(webhook1.campaign_id).to_a
      assert_equal [@spu], SponsorsPatreonUser.for_patreon_campaign(webhook2.campaign_id).to_a
    end

    test "returns Patreon users who own the Patreon tier with the given campaign ID" do
      assert_equal [@spu], SponsorsPatreonUser.for_patreon_campaign(@patreon_tier.campaign_id).to_a
    end
  end

  context "#clean_up_webhooks_on_patreon" do
    test "deletes our webhooks on Patreon and any corresponding SponsorsPatreonCampaignWebhook records" do
      refute_nil @spu.patreon_client, "need a SponsorsPatreonUser that has a Patreon API client"
      webhook1, webhook2 = create_pair(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: @spu)
      webhook3_id = webhook2.webhook_id + "abc"

      SponsorsPatreonClient.any_instance.expects(:get_webhooks).once.returns({
        "data" => [
          { "id" => webhook1.webhook_id },
          { "id" => webhook2.webhook_id },
          {
            "id" => webhook3_id,
            "attributes" => { "uri" => SyncSponsorsPatreonWebhooks::RECEIVING_URL,
              "triggers" => PatreonWebhookEvent.triggers },
          },
        ]
      })

      SponsorsPatreonClient.any_instance.expects(:delete_webhook).once.with(webhook1.webhook_id)
      SponsorsPatreonClient.any_instance.expects(:delete_webhook).once.with(webhook2.webhook_id)
      SponsorsPatreonClient.any_instance.expects(:delete_webhook).once.with(webhook3_id)

      assert_difference("SponsorsPatreonCampaignWebhook.count", -2) do
        @spu.clean_up_webhooks_on_patreon
      end

      refute SponsorsPatreonCampaignWebhook.exists?(webhook1.id)
      refute SponsorsPatreonCampaignWebhook.exists?(webhook2.id)
    end
  end

  context "#enqueue_refresh_tokens_job" do
    test "enqueues a job for some time in the future based on the given token expiration time offset" do
      spu = create(:sponsors_patreon_user)
      expires_in = 2678400

      freeze_time do
        expected_enqueue_time = Time.now + expires_in.seconds -
          SponsorsPatreonUser::TOKEN_EXPIRY_GRACE_PERIOD_IN_DAYS.days

        assert_enqueued_with(job: RefreshSponsorsPatreonTokensJob, at: expected_enqueue_time) do
          spu.enqueue_refresh_tokens_job(expires_in: expires_in)
        end
      end
    end
  end

  context "#subscribe_to_webhooks?" do
    test "false when a webhook exists for each Patreon campaign" do
      create_pair(:sponsors_patreon_tier, sponsors_patreon_user: @spu)
      @spu.sponsors_patreon_tiers.each do |tier|
        create(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: @spu, campaign_id: tier.campaign_id)
      end

      refute_predicate @spu, :subscribe_to_webhooks?
    end

    test "true when a Patreon campaign does not have a webhook" do
      patreon_tier1, patreon_tier2 = create_pair(:sponsors_patreon_tier, sponsors_patreon_user: @spu)
      create(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: @spu, campaign_id: patreon_tier1.campaign_id)

      assert_predicate @spu, :subscribe_to_webhooks?
    end

    test "false if no Patreon tiers exist" do
      @spu.sponsors_patreon_tiers.destroy_all
      refute_predicate @spu.reload, :subscribe_to_webhooks?
    end

    test "true even if no Patreon tier meets the maintainer's minimum amount but we know a campaign ID" do
      @spu.sponsors_listing.update!(min_custom_tier_amount_in_cents: 50_00)
      @patreon_tier.update(amount_in_cents: 25_00)

      assert_predicate @spu, :subscribe_to_webhooks?
    end
  end

  context "enabled_as_sponsorable scope" do
    test "returns Patreon users who have opted to allow receiving sponsorships via Patreon" do
      patreon_user1 = create(:sponsors_patreon_user, enabled_as_sponsorable: true)
      patreon_user2 = create(:sponsors_patreon_user, enabled_as_sponsorable: false)

      result = SponsorsPatreonUser.enabled_as_sponsorable.where(id: [patreon_user1.id, patreon_user2.id]).to_a

      assert_equal [patreon_user1], result
    end
  end

  context "validations" do
    test "requires a user" do
      spu = SponsorsPatreonUser.new(user: nil)
      refute_predicate spu, :valid?
      assert_includes spu.errors[:user], "must exist"
    end

    test "requires a unique user per Patreon user ID" do
      spu2 = SponsorsPatreonUser.new(user_id: @spu.user_id, patreon_user_id: @spu.patreon_user_id)
      refute_predicate spu2, :valid?
      assert_includes spu2.errors.full_messages_for(:user_id), "GitHub account is already connected with Patreon"
    end

    test "requires a Patreon user ID" do
      spu = SponsorsPatreonUser.new(patreon_user_id: nil)
      refute_predicate spu, :valid?
      assert_includes spu.errors[:patreon_user_id], "can't be blank"
    end

    test "requires a unique Patreon user ID" do
      spu2 = SponsorsPatreonUser.new(patreon_user_id: @spu.patreon_user_id)
      refute_predicate spu2, :valid?
      assert_includes spu2.errors.full_messages_for(:patreon_user_id),
        "Patreon account is already associated with another GitHub account"
    end

    test "gives more detail about dupe Patreon user when the viewer has admin access to the GitHub account tied to the existing record" do
      org = create(:organization, admin: @spu.user)
      bad_spu = SponsorsPatreonUser.new(patreon_user_id: @spu.patreon_user_id, user: org,
        patreon_email: "foo@example.com")
      GitHub.context.push(actor_id: @spu.user_id)

      refute_predicate bad_spu, :valid?
      assert_includes bad_spu.errors.full_messages, "You must disconnect @#{@spu.user.display_login}'s GitHub " \
        "account from Patreon first"
    end

    test "does not give more detail about dupe Patreon user when the viewer lacks admin access to the GitHub account tied to the existing record" do
      org = create(:organization, admin: @spu.user)
      org_member = create(:user)
      org.add_member(org_member)
      bad_spu = SponsorsPatreonUser.new(patreon_user_id: @spu.patreon_user_id, user: org,
        patreon_email: "foo@example.com")
      GitHub.context.push(actor_id: org_member.id)

      refute_predicate bad_spu, :valid?
      refute_includes bad_spu.errors.full_messages, "You must disconnect @#{@spu.user.display_login}'s GitHub " \
        "account from Patreon first"
    end

    test "does not give more detail about dupe Patreon user when the viewer is unknown" do
      org = create(:organization, admin: @spu.user)
      bad_spu = SponsorsPatreonUser.new(patreon_user_id: @spu.patreon_user_id, user: org,
        patreon_email: "foo@example.com")
      GitHub.context.push(actor_id: nil)

      refute_predicate bad_spu, :valid?
      refute_includes bad_spu.errors.full_messages, "You must disconnect @#{@spu.user.display_login}'s GitHub " \
        "account from Patreon first"
    end

    test "requires a Patreon email" do
      spu = SponsorsPatreonUser.new(patreon_email: nil)
      refute_predicate spu, :valid?
      assert_includes spu.errors[:patreon_email], "can't be blank"
    end
  end

  context "#has_patreon_tier_with_value?" do
    test "returns true when the user has a Patreon tier for the given amount" do
      create(:sponsors_patreon_tier, amount_in_cents: 123456, sponsors_patreon_user: @spu)
      assert @spu.has_patreon_tier_with_value?(123456)
    end

    test "returns false when the user has no Patreon tier at the given amount" do
      create(:sponsors_patreon_tier, amount_in_cents: 456, sponsors_patreon_user: @spu)
      refute @spu.has_patreon_tier_with_value?(500)
    end
  end

  context "#any_valid_patreon_tiers?" do
    test "returns true when Patreon tier exists and maintainer has no min amount" do
      listing = create(:sponsors_listing, min_custom_tier_amount_in_cents: nil)
      spu = create(:sponsors_patreon_user, user: listing.sponsorable)
      create(:sponsors_patreon_tier, sponsors_patreon_user: spu)

      assert_predicate spu, :any_valid_patreon_tiers?
    end

    test "returns true when patreon tier exists with amount that exceed maintainer's min amount" do
      listing = create(:sponsors_listing, min_custom_tier_amount_in_cents: 5_00)
      spu = create(:sponsors_patreon_user, user: listing.sponsorable)
      create(:sponsors_patreon_tier, sponsors_patreon_user: spu, amount_in_cents: 10_00)

      assert_predicate spu, :any_valid_patreon_tiers?
    end

    test "returns true when a SponsorsPatreonTier exists for the user and maintainer has no min amount" do
      listing = create(:sponsors_listing, min_custom_tier_amount_in_cents: nil)
      spu = create(:sponsors_patreon_user, :with_tier, user: listing.sponsorable)
      assert_predicate spu, :any_valid_patreon_tiers?
    end

    test "returns true when a SponsorsPatreonTier exists for the user whose value exceeds the maintainer's min amount" do
      listing = create(:sponsors_listing, min_custom_tier_amount_in_cents: 2_00)
      spu = create(:sponsors_patreon_user, user: listing.sponsorable)
      create(:sponsors_patreon_tier, sponsors_patreon_user: spu, amount_in_cents: 3_00)
      assert_predicate spu, :any_valid_patreon_tiers?
    end

    test "returns false when no SponsorsPatreonTier's value exceeds the maintainer's min amount" do
      listing = create(:sponsors_listing, min_custom_tier_amount_in_cents: 2_00)
      spu = create(:sponsors_patreon_user, user: listing.sponsorable)
      create(:sponsors_patreon_tier, sponsors_patreon_user: spu, amount_in_cents: 1_00)
      refute_predicate spu, :any_valid_patreon_tiers?
    end

    test "returns false when no SponsorsPatreonTier records exist for the user" do
      spu = create(:sponsors_patreon_user)
      refute_predicate spu, :any_valid_patreon_tiers?
    end
  end

  context "#any_patreon_tiers_not_meeting_maintainer_minimum?" do
    test "returns true when maintainer has a minimum amount exceeding the Patreon tier" do
      listing = create(:sponsors_listing, min_custom_tier_amount_in_cents: 25_00)
      spu = create(:sponsors_patreon_user, user: listing.sponsorable)
      create(:sponsors_patreon_tier, sponsors_patreon_user: spu, amount_in_cents: 2_00)

      assert_predicate spu, :any_patreon_tiers_not_meeting_maintainer_minimum?
    end

    test "returns false when maintainer has no default Patreon tier and no SponsorsPatreonTier records" do
      listing = create(:sponsors_listing, min_custom_tier_amount_in_cents: 9_00)
      spu = SponsorsPatreonUser.new(user: listing.sponsorable)

      refute_predicate spu, :any_patreon_tiers_not_meeting_maintainer_minimum?
    end

    test "returns false when maintainer does not have a minimum amount" do
      listing = create(:sponsors_listing, min_custom_tier_amount_in_cents: nil)
      spu = create(:sponsors_patreon_user, user: listing.sponsorable)
      create(:sponsors_patreon_tier, sponsors_patreon_user: spu, amount_in_cents: 2_00)

      refute_predicate spu, :any_patreon_tiers_not_meeting_maintainer_minimum?
    end
  end

  context "#assign_from_identity_response" do
    test "sets fields from Patreon identity API result that has no published campaign" do
      identity_response = {
        "data" => {
          "attributes" => { "email" => "cheshire137@github.com", "full_name" => "cheshire137" },
          "id" => "88653153",
          "type" => "user",
        },
        "links" => { "self" => "https://www.patreon.com/api/oauth2/v2/user/88653153" },
      }
      spu = SponsorsPatreonUser.new(patreon_email: nil, patreon_user_id: nil, patreon_username: nil)

      spu.assign_from_identity_response(identity_response)

      assert_equal "cheshire137@github.com", spu.patreon_email
      assert_equal "88653153", spu.patreon_user_id
      assert_equal "cheshire137", spu.patreon_username
    end

    test "sets fields from Patreon identity API result that has an unpublished campaign" do
      identity_response = {
        "data" => {
          "attributes" => { "email" => "darby@example.com", "full_name" => "space smile's patron name" },
          "id" => "2799531",
          "type" => "user",
        },
        "included" => [{
          "attributes" => { "published_at" => nil, "vanity" => "oauth" },
          "id" => "368121",
          "type" => "campaign",
        }],
        "links" => { "self" => "https://www.patreon.com/api/oauth2/v2/user/2799531" },
      }
      spu = SponsorsPatreonUser.new(patreon_email: nil, patreon_user_id: nil, patreon_username: nil)

      spu.assign_from_identity_response(identity_response)

      assert_equal "darby@example.com", spu.patreon_email
      assert_equal "2799531", spu.patreon_user_id
      assert_equal "space smile's patron name", spu.patreon_username
    end

    test "sets fields from Patreon identity API result that has a published campaign" do
      identity_response = {
        "data" => {
          "attributes" => { "email" => "darby@example.com", "full_name" => "space smile's patron name" },
          "id" => "2799531",
          "type" => "user",
        },
        "included" => [{
          "attributes" => { "published_at" => "2016-09-07T23:20:56.000+00:00", "vanity" => "oauth" },
          "id" => "368121",
          "type" => "campaign",
        }],
        "links" => { "self" => "https://www.patreon.com/api/oauth2/v2/user/2799531" },
      }
      spu = SponsorsPatreonUser.new(patreon_email: nil, patreon_user_id: nil, patreon_username: nil)

      spu.assign_from_identity_response(identity_response)

      assert_equal "darby@example.com", spu.patreon_email
      assert_equal "2799531", spu.patreon_user_id
      assert_equal "oauth", spu.patreon_username
    end
  end

  context "#patreon_campaign_ids" do
    test "returns a unique list of the user's Patreon campaign IDs" do
      spu = create(:sponsors_patreon_user)
      create(:sponsors_patreon_tier, sponsors_patreon_user: spu, campaign_id: "1234567", amount_in_cents: 100)
      create(:sponsors_patreon_tier, sponsors_patreon_user: spu, campaign_id: "1234567", amount_in_cents: 200)
      create(:sponsors_patreon_tier, sponsors_patreon_user: spu, campaign_id: "abc123", amount_in_cents: 250)

      result = spu.patreon_campaign_ids

      assert_same_elements %w[1234567 abc123], result
    end
  end

  context "#sync_sponsors_patreon_user" do
    test "delays specified number of minutes" do
      # Wait long enough to allow enqueuing the same job, since creating the SponsorsPatreonUser enqueues one:
      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      freeze_time

      assert_enqueued_with(
        job: SyncSponsorsPatreonUserJob,
        args: [@spu, { actor: nil }],
        at: 10.minutes.from_now,
      ) do
        assert_enqueued_with(
          job: SyncPatreonSponsorshipsJob,
          args: [@spu, { actor: nil }],
          at: 10.minutes.from_now,
        ) do
          @spu.sync_sponsors_patreon_user(delay_in_minutes: 10)
        end
      end
    end

    test "includes sponsorships if user is sponsorable" do
      assert_predicate @spu.user, :sponsorable?

      # Wait long enough to allow enqueuing the same job, since creating the SponsorsPatreonUser enqueues one:
      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_enqueued_with(job: SyncSponsorsPatreonUserJob, args: [@spu, { actor: nil }]) do
        assert_enqueued_with(job: SyncPatreonSponsorshipsJob, args: [@spu, { actor: nil }]) do
          @spu.sync_sponsors_patreon_user
        end
      end
    end

    test "does not include sponsorships if user is sponsor" do
      spu = create(:sponsors_patreon_user, :sponsor)
      refute_predicate spu.user, :sponsorable?

      # Wait long enough to allow enqueuing the same job, since creating the SponsorsPatreonUser enqueues one:
      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_enqueued_with(job: SyncSponsorsPatreonUserJob, args: [spu, { actor: nil }]) do
        assert_no_enqueued_jobs(only: SyncPatreonSponsorshipsJob) do
          spu.sync_sponsors_patreon_user
        end
      end
    end

    test "includes sponsorships when explicitly specified" do
      spu = create(:sponsors_patreon_user, :sponsor)
      refute_predicate spu.user, :sponsorable?, "need a user who would normally not have sponsorships included"

      # Wait long enough to allow enqueuing the same job, since creating the SponsorsPatreonUser enqueues one:
      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_enqueued_with(job: SyncSponsorsPatreonUserJob, args: [spu, { actor: nil }]) do
        assert_enqueued_with(job: SyncPatreonSponsorshipsJob, args: [spu, { actor: nil }]) do
          spu.sync_sponsors_patreon_user(include_sponsorships: true)
        end
      end
    end

    test "omits sponsorships when explicitly specified" do
      assert_predicate @spu.user, :sponsorable?, "need a user who would normally have sponsorships included"

      # Wait long enough to allow enqueuing the same job, since creating the SponsorsPatreonUser enqueues one:
      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_enqueued_with(job: SyncSponsorsPatreonUserJob, args: [@spu, { actor: nil }]) do
        assert_no_enqueued_jobs(only: SyncPatreonSponsorshipsJob) do
          @spu.sync_sponsors_patreon_user(include_sponsorships: false)
        end
      end
    end

    test "passes along actor when enqueuing job" do
      org_admin = create(:user)
      org = create(:organization, :sponsorable, admin: org_admin)
      spu = create(:sponsors_patreon_user, user: org)
      spu.actor = org_admin

      # Wait long enough to allow enqueuing the same job, since creating the SponsorsPatreonUser enqueues one:
      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_enqueued_with(job: SyncSponsorsPatreonUserJob, args: [spu, { actor: org_admin }]) do
        assert_enqueued_with(job: SyncPatreonSponsorshipsJob, args: [spu, { actor: org_admin }]) do
          spu.sync_sponsors_patreon_user
        end
      end
    end

    test "does not include sponsorships if user does not exist" do
      @spu.user.destroy!
      assert_nil @spu.reload.user

      # Wait long enough to allow enqueuing the same job, since creating the SponsorsPatreonUser enqueues one:
      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_enqueued_with(job: SyncSponsorsPatreonUserJob, args: [@spu, { actor: nil }]) do
        assert_no_enqueued_jobs(only: SyncPatreonSponsorshipsJob) do
          @spu.sync_sponsors_patreon_user
        end
      end
    end
  end

  context "sponsors_listing relation" do
    test "returns the SponsorsListing tied to the user when they have one" do
      user = create(:user, :verified)
      listing = create(:sponsors_listing, sponsorable: user)
      spu = create(:sponsors_patreon_user, user: user)

      assert_equal listing, spu.sponsors_listing
    end

    test "returns nil when the user does not have a SponsorsListing" do
      user = create(:user, :verified)
      spu = create(:sponsors_patreon_user, :sponsor, user: user)

      assert_nil spu.sponsors_listing
    end
  end

  context "#patreon_client" do
    test "returns a SponsorsPatreonClient when there are access and refresh tokens" do
      spu = SponsorsPatreonUser.new(patreon_access_token: "abc", patreon_refresh_token: "123")
      assert_instance_of SponsorsPatreonClient, spu.patreon_client
    end

    test "returns nil when there is no access token" do
      spu = SponsorsPatreonUser.new(patreon_access_token: nil, patreon_refresh_token: "123")
      assert_nil spu.patreon_client
    end

    test "returns nil when there is no refresh token" do
      spu = SponsorsPatreonUser.new(patreon_access_token: "abc123", patreon_refresh_token: "")
      assert_nil spu.patreon_client
    end
  end

  context "#patreon_link" do
    test "returns link when user has a Patreon campaign" do
      spu = create(:sponsors_patreon_user)
      create(:sponsors_patreon_tier, sponsors_patreon_user: spu)

      assert_equal "https://patreon.com/#{spu.patreon_username}", spu.patreon_link
    end

    test "returns nil when user does not have a Patreon campaign" do
      spu = create(:sponsors_patreon_user)

      assert_nil spu.patreon_link
    end
  end

  context "#patreon_membership_link" do
    test "returns link when user has a Patreon campaign" do
      spu = create(:sponsors_patreon_user)
      create(:sponsors_patreon_tier, sponsors_patreon_user: spu)

      assert_equal "https://patreon.com/#{spu.patreon_username}/membership", spu.patreon_membership_link
    end

    test "returns nil when user does not have a Patreon campaign" do
      spu = create(:sponsors_patreon_user)

      assert_nil spu.patreon_link
    end
  end

  context "sponsors_tiers relation" do
    test "returns the Sponsors tiers tied to the listing when the user has one" do
      user = create(:user, :verified)
      listing = create(:sponsors_listing, tier_count: 0, sponsorable: user)
      tier1, tier2 = create_pair(:sponsors_tier, sponsors_listing: listing)
      spu = create(:sponsors_patreon_user, user: user)

      assert_same_elements [tier1, tier2], spu.sponsors_tiers
    end

    test "returns an empty list when the user does not have a SponsorsListing" do
      user = create(:user, :verified)
      spu = create(:sponsors_patreon_user, :sponsor, user: user)

      assert_empty spu.sponsors_tiers
    end
  end

  context "for_user scope" do
    test "filters to just records tied to the given user" do
      user1, user2 = create_pair(:user, :verified)
      spu1 = create(:sponsors_patreon_user, user: user1)
      spu2 = create(:sponsors_patreon_user, user: user2)

      assert_equal [spu1], SponsorsPatreonUser.for_user(user1)
    end
  end

  context "for_patreon_user scope" do
    test "filters to just records tied to the given Patreon user ID" do
      spu1 = create(:sponsors_patreon_user, patreon_user_id: "8675309")
      spu2 = create(:sponsors_patreon_user, patreon_user_id: "1234567")

      assert_equal [spu2], SponsorsPatreonUser.for_patreon_user("1234567")
    end
  end

  context "before destroy" do
    test "cancels active Patreon sponsorships as funder and maintainer" do
      non_patreon_sponsorship = create(:sponsorship, sponsor: @spu.user)
      as_sponsorable = create(:sponsorship, :patreon, sponsorable: @spu.user)
      as_patron = create(:sponsorship, :patreon, sponsor: @spu.user)

      VCR.use_cassette("patreon/delete_webhook") do
        VCR.use_cassette("patreon/get_webhooks_one_result") do
          @spu.destroy!
        end
      end

      assert_predicate non_patreon_sponsorship.reload, :active?
      refute_predicate as_sponsorable.reload, :active?
      refute_predicate as_patron.reload, :active?
    end

    # https://github.com/github/sponsors/issues/5437
    test "cancels sponsorships even when user no longer exists" do
      sponsorship_as_sponsorable = create(:sponsorship, :patreon, sponsorable: @spu.user)
      sponsorship_as_patron = create(:sponsorship, :patreon, sponsor: @spu.user)
      @spu.user.delete

      VCR.use_cassette("patreon/delete_webhook") do
        VCR.use_cassette("patreon/get_webhooks_one_result") do
          @spu.reload.destroy!
        end
      end

      refute_predicate sponsorship_as_sponsorable.reload, :active?
      refute_predicate sponsorship_as_patron.reload, :active?
    end

    test "cancels a sponsoring user's sponsorships" do
      non_patreon_sponsorship = create(:sponsorship, sponsor: @spu.user)
      patreon_sponsorship = create(:sponsorship, :patreon, sponsor: @spu.user)

      VCR.use_cassette("patreon/delete_webhook") do
        VCR.use_cassette("patreon/get_webhooks_one_result") do
          @spu.destroy!
        end
      end

      assert_predicate non_patreon_sponsorship.reload, :active?
      refute_predicate patreon_sponsorship.reload, :active?
    end

    test "destroys webhooks on Patreon and in our database" do
      spu = create(:sponsors_patreon_user)
      patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: spu)
      webhook = create(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: spu,
        campaign_id: patreon_tier.campaign_id, webhook_id: "722598") # see VCR cassette
      webhook_event = create(:patreon_webhook_event, account_id: spu.patreon_user_id)

      SponsorsPatreonClient.any_instance.expects(:delete_webhook).at_least_once.with(webhook.webhook_id)

      assert_difference({ "SponsorsPatreonCampaignWebhook.count" => -1, "PatreonWebhookEvent.count" => -1 }) do
        SyncSponsorsPatreonWebhooks.stub_const(:RECEIVING_URL, @fake_receiving_url) do
          VCR.use_cassette("patreon/get_webhooks_one_result") do
            spu.destroy!
          end
        end
      end

      refute SponsorsPatreonCampaignWebhook.exists?(webhook.id)
      refute PatreonWebhookEvent.exists?(webhook_event.id)
    end

    test "instruments sponsorship cancellation request to Hydro" do
      patreon_sponsorship = create(:sponsorship, :patreon, sponsor: @spu.user)

      VCR.use_cassette("patreon/delete_webhook") do
        VCR.use_cassette("patreon/get_webhooks_one_result") do
          @spu.destroy!
        end
      end

      expected_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(patreon_sponsorship),
        tier: Hydro::EntitySerializer.sponsors_tier(patreon_sponsorship.tier),
        listing: Hydro::EntitySerializer.sponsors_listing(patreon_sponsorship.sponsors_listing),
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          patreon_sponsorship.sponsors_listing_stafftools_metadata,
        ),
        actor: Hydro::EntitySerializer.user(patreon_sponsorship.sponsor),
        sponsor: Hydro::EntitySerializer.user(patreon_sponsorship.sponsor),
        sponsorable: Hydro::EntitySerializer.user(patreon_sponsorship.sponsorable),
        reason: :PATREON_ACCOUNT_DISCONNECTED,
        forced: true
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end
  end

  context "after create callback" do
    test "enqueues a SyncSponsorsPatreonUserJob" do
      assert_enqueued_with(job: SyncSponsorsPatreonUserJob) do
        SponsorsPatreonUser.create(
          user: create(:verified_user),
          patreon_user_id: "123",
          patreon_email: "abc@example.com",
          patreon_access_token: "XXX",
          patreon_refresh_token: "XXX"
        )
      end
    end
  end

  context "#min_patreon_tier_amount_in_cents" do
    test "returns minimum amount among user's Patreon tiers" do
      @patreon_tier.update!(amount_in_cents: 5_00)
      min_tier = create(:sponsors_patreon_tier, amount_in_cents: 1_00, sponsors_patreon_user: @spu)

      assert_equal 1_00, @spu.min_patreon_tier_amount_in_cents
    end

    test "returns nil when user has no Patreon tiers" do
      @spu.sponsors_patreon_tiers.destroy_all

      assert_nil @spu.min_patreon_tier_amount_in_cents
    end
  end
end
