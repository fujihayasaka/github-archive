# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SyncPatreonSponsorshipsJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @spu = create(:sponsors_patreon_user)
  end

  setup do
    @datadog_prefix = SyncPatreonSponsorshipsJob::DATADOG_PREFIX
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: SyncPatreonSponsorshipsJob, args: [@spu]
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: SyncPatreonSponsorshipsJob, args: [@spu]
  end

  if GitHub.sponsors_enabled?
    test "calls the sponsorships sync in write mode when  there is only one batch of memberships to process" do
      actor = @spu.user
      former_sponsor = create(:sponsors_patreon_user, :sponsor).user
      sponsorship_to_cancel = create(:sponsorship, :patreon, sponsor: former_sponsor, sponsorable: @spu.user)

      data = SponsorsPatreonSponsorshipLoader::Result.new(
        sponsorships_to_cancel: Set.new([sponsorship_to_cancel]),
        membership_next_page_cursors_by_campaign_id: {},
        sponsorships_to_update: Set.new,
        target_sponsorship_cents_by_sponsor_id: {},
      )
      SponsorsPatreonSponsorshipLoader.expects(:call).once.with(
        sponsors_patreon_user: @spu,
        membership_page_cursors_by_campaign_id: {},
        max_membership_pages: 20,
        target_sponsorship_cents_by_sponsor_id: {},
      ).returns(data)
      CreateAndUpdatePatreonSponsorships.expects(:call).once.with(sponsors_patreon_user: @spu, data: data,
        actor: actor)
      CancelPatreonSponsorships.expects(:call).once.with(sponsors_patreon_user: @spu,
        sponsorships_to_cancel: [sponsorship_to_cancel].to_set, actor: actor, write_mode: true)

      SyncPatreonSponsorshipsJob.perform_now(@spu, actor: actor)

      refute_dogstats_increment("#{@datadog_prefix}.multiple_membership_batches")
    end

    test "just logs cancellations when d the first batch of memberships is being processed" do
      actor = @spu.user
      former_sponsor = create(:sponsors_patreon_user, :sponsor).user
      sponsorship_to_cancel = create(:sponsorship, :patreon, sponsor: former_sponsor, sponsorable: @spu.user)

      data = SponsorsPatreonSponsorshipLoader::Result.new(
        sponsorships_to_cancel: Set.new([sponsorship_to_cancel]),
        sponsorships_to_update: Set.new,
        target_sponsorship_cents_by_sponsor_id: { 123 => 500 },
        membership_next_page_cursors_by_campaign_id: { "12345" => "jifdosajdios" },
      )
      SponsorsPatreonSponsorshipLoader.expects(:call).once.with(
        sponsors_patreon_user: @spu,
        membership_page_cursors_by_campaign_id: {},
        max_membership_pages: 20,
        target_sponsorship_cents_by_sponsor_id: {},
      ).returns(data)
      CreateAndUpdatePatreonSponsorships.expects(:call).once.with(
        sponsors_patreon_user: @spu,
        data: data,
        actor: actor,
      )
      CancelPatreonSponsorships.expects(:call).once.with(sponsors_patreon_user: @spu,
        sponsorships_to_cancel: [sponsorship_to_cancel].to_set, actor: actor, write_mode: false)

      assert_enqueued_with(
        job: SyncPatreonSponsorshipsJob,
        args: [@spu, {
          actor: actor,
          membership_page_cursors_by_campaign_id: { "12345" => "jifdosajdios" },
          max_membership_pages: 20,
          target_sponsorship_cents_by_sponsor_id: { "123" => 500 },
        }],
      ) do
        SyncPatreonSponsorshipsJob.perform_now(@spu, actor: actor)
      end

      # This was the first batch of many, so don't expect an increment:
      refute_dogstats_increment("#{@datadog_prefix}.multiple_membership_batches")
    end

    test "just logs cancellations when a batch of memberships other than the first or last is being processed" do
      actor = @spu.user
      former_sponsor = create(:sponsors_patreon_user, :sponsor).user
      sponsorship_to_cancel = create(:sponsorship, :patreon, sponsor: former_sponsor, sponsorable: @spu.user)

      data = SponsorsPatreonSponsorshipLoader::Result.new(
        sponsorships_to_cancel: Set.new([sponsorship_to_cancel]),
        sponsorships_to_update: Set.new,
        target_sponsorship_cents_by_sponsor_id: { 123 => 500 },
        membership_next_page_cursors_by_campaign_id: { "67890" => "foobar" }, # no more pages of results
      )
      SponsorsPatreonSponsorshipLoader.expects(:call).once.with(
        sponsors_patreon_user: @spu,
        membership_page_cursors_by_campaign_id: { "12345" => "jifdosajdios" },
        max_membership_pages: 20,
        target_sponsorship_cents_by_sponsor_id: {},
      ).returns(data)
      CreateAndUpdatePatreonSponsorships.expects(:call).once.with(
        sponsors_patreon_user: @spu,
        data: data,
        actor: actor,
      )
      CancelPatreonSponsorships.expects(:call).once.with(sponsors_patreon_user: @spu,
        sponsorships_to_cancel: [sponsorship_to_cancel].to_set, actor: actor, write_mode: false)

      assert_enqueued_with(
        job: SyncPatreonSponsorshipsJob,
        args: [@spu, {
          actor: actor,
          membership_page_cursors_by_campaign_id: { "67890" => "foobar" },
          max_membership_pages: 20,
          target_sponsorship_cents_by_sponsor_id: { "123" => 500 },
        }],
      ) do
        SyncPatreonSponsorshipsJob.perform_now(@spu, actor: actor,
          membership_page_cursors_by_campaign_id: { "12345" => "jifdosajdios" })
      end

      assert_dogstats_increment(1, "#{@datadog_prefix}.multiple_membership_batches")
    end

    test "just logs cancellations when the last batch of memberships is being processed" do
      actor = @spu.user
      former_sponsor = create(:sponsors_patreon_user, :sponsor).user
      sponsorship_to_cancel = create(:sponsorship, :patreon, sponsor: former_sponsor, sponsorable: @spu.user)

      data = SponsorsPatreonSponsorshipLoader::Result.new(
        sponsorships_to_cancel: Set.new([sponsorship_to_cancel]),
        sponsorships_to_update: Set.new,
        target_sponsorship_cents_by_sponsor_id: { 123 => 500 },
        membership_next_page_cursors_by_campaign_id: {}, # no more pages of results
      )
      SponsorsPatreonSponsorshipLoader.expects(:call).once.with(
        sponsors_patreon_user: @spu,
        membership_page_cursors_by_campaign_id: { "12345" => "jifdosajdios" },
        max_membership_pages: 20,
        target_sponsorship_cents_by_sponsor_id: {},
      ).returns(data)
      CreateAndUpdatePatreonSponsorships.expects(:call).once.with(
        sponsors_patreon_user: @spu,
        data: data,
        actor: actor,
      )
      CancelPatreonSponsorships.expects(:call).once.with(sponsors_patreon_user: @spu,
        sponsorships_to_cancel: [sponsorship_to_cancel].to_set, actor: actor, write_mode: false)

      assert_no_enqueued_jobs(only: SyncPatreonSponsorshipsJob) do
        SyncPatreonSponsorshipsJob.perform_now(@spu, actor: actor,
          membership_page_cursors_by_campaign_id: { "12345" => "jifdosajdios" })
      end

      assert_dogstats_increment(1, "#{@datadog_prefix}.multiple_membership_batches")
    end

    test "passes along membership pagination cursors to the service model" do
      GitHub.context.push(actor_id: @spu.user_id)
      sponsor_id = 123
      sponsor_cents = 500
      membership_page_cursors_by_campaign_id = { "123" => "cursor1", "456" => "cursor2" }

      data = SponsorsPatreonSponsorshipLoader::Result.new(
        membership_next_page_cursors_by_campaign_id: {},
        target_sponsorship_cents_by_sponsor_id: { sponsor_id => sponsor_cents },
        sponsorships_to_cancel: Set.new,
        sponsorships_to_update: Set.new,
      )
      SponsorsPatreonSponsorshipLoader.expects(:call).once.with(
        sponsors_patreon_user: @spu,
        membership_page_cursors_by_campaign_id: membership_page_cursors_by_campaign_id,
        max_membership_pages: 3,
        target_sponsorship_cents_by_sponsor_id: { sponsor_id => sponsor_cents },
      ).returns(data)
      CreateAndUpdatePatreonSponsorships.expects(:call).once.with(sponsors_patreon_user: @spu, data: data,
        actor: @spu.user)
      CancelPatreonSponsorships.expects(:call).never

      assert_logged(
        Body: "Processing later batch of Patreon sponsorships",
        "actor.id": @spu.user_id,
        "gh.catalog_service": "github/github_sponsors",
        "code.namespace": "SyncPatreonSponsorshipsJob",
        "sponsorable.id": @spu.user_id,
      ) do
        assert_no_enqueued_jobs(only: SyncPatreonSponsorshipsJob) do
          SyncPatreonSponsorshipsJob.perform_now(@spu,
            max_membership_pages: 3,
            membership_page_cursors_by_campaign_id: membership_page_cursors_by_campaign_id,
            target_sponsorship_cents_by_sponsor_id: { sponsor_id.to_s => sponsor_cents },
          )
        end
      end

      assert_dogstats_increment(1, "#{@datadog_prefix}.multiple_membership_batches")
    end

    test "enqueues job to continue with the next batch of Patreon memberships" do
      starting_page_cursor = nil
      next_page_cursor = "02B9AS9r0rVy7smJCVpWQPdNob"
      campaign_id = "459978"
      sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
      actor = sponsor_spu.user
      pages_per_batch = 1

      assert_logged(
        Body: "Processing later batch of Patreon sponsorships",
        "actor.id": actor.id,
        "gh.catalog_service": "github/github_sponsors",
        "code.namespace": "SyncPatreonSponsorshipsJob",
        "sponsorable.id": @spu.user_id,
      ) do
        assert_enqueued_with(
          job: SyncPatreonSponsorshipsJob,
          args: [@spu, {
            actor: actor,
            membership_page_cursors_by_campaign_id: { campaign_id => next_page_cursor },
            max_membership_pages: pages_per_batch,
            target_sponsorship_cents_by_sponsor_id: { sponsor_spu.user_id.to_s => 100 },
          }],
        ) do
          VCR.use_cassette("patreon/get_campaigns_and_memberships") do
            SyncPatreonSponsorshipsJob.perform_now(@spu, actor: actor, max_membership_pages: pages_per_batch,
              membership_page_cursors_by_campaign_id: { campaign_id => starting_page_cursor })
          end
        end
      end

      assert_dogstats_increment(1, "#{@datadog_prefix}.multiple_membership_batches")
    end

    test "measures how long creating, updating, and cancelling sponsorships takes" do
      new_sponsor = create(:sponsors_patreon_user, :sponsor).user
      current_sponsor = create(:sponsors_patreon_user, :sponsor).user
      sponsorship_to_update = create(:sponsorship, :patreon, sponsor: current_sponsor, sponsorable: @spu.user)
      former_sponsor = create(:sponsors_patreon_user, :sponsor).user
      sponsorship_to_cancel = create(:sponsorship, :patreon, sponsor: former_sponsor, sponsorable: @spu.user)

      data = SponsorsPatreonSponsorshipLoader::Result.new(
        membership_next_page_cursors_by_campaign_id: {},
        sponsorships_to_cancel: Set.new([sponsorship_to_cancel]),
        sponsorships_to_update: Set.new([sponsorship_to_update]),
        target_sponsorship_cents_by_sponsor_id: {
          new_sponsor.id => 100,
          current_sponsor.id => sponsorship_to_update.monthly_price_in_cents + 100,
        },
      )
      SponsorsPatreonSponsorshipLoader.expects(:call).once.with(
        sponsors_patreon_user: @spu,
        membership_page_cursors_by_campaign_id: {},
        max_membership_pages: 10,
        target_sponsorship_cents_by_sponsor_id: {},
      ).returns(data)

      SyncPatreonSponsorshipsJob.perform_now(@spu, actor: User.staff_user, max_membership_pages: 10)

      assert_dogstats_timing(1, "#{CreateAndUpdatePatreonSponsorships::DATADOG_PREFIX}.create_sponsorships")
      assert_dogstats_timing(1, "#{CancelPatreonSponsorships::DATADOG_PREFIX}.cancel_sponsorships")
      assert_dogstats_timing(1, "#{CreateAndUpdatePatreonSponsorships::DATADOG_PREFIX}.update_sponsorships")
    end

    test "measures how long it takes to load membership data" do
      sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette

      VCR.use_cassette("patreon/get_campaigns_and_memberships") do
        SyncPatreonSponsorshipsJob.perform_now(@spu, actor: sponsor_spu.user)
      end

      assert_dogstats_timing(1, "#{SponsorsPatreonClient::DATADOG_PREFIX}.get_memberships",
        tags: ["max_pages:20", "first_batch:true"])
    end

    # https://github.com/github/sponsors/issues/5337
    test "no-op when SponsorsPatreonUser is for an account without a SponsorsListing" do
      non_sponsorable_patreon_user = create(:sponsors_patreon_user, :sponsor)
      actor = non_sponsorable_patreon_user.user
      assert_nil actor.sponsors_listing, "need a user without a SponsorsListing"

      CreateAndUpdatePatreonSponsorships.expects(:call).never
      CancelPatreonSponsorships.expects(:call).never

      assert_no_enqueued_jobs(only: SyncPatreonSponsorshipsJob) do
        SyncPatreonSponsorshipsJob.perform_now(non_sponsorable_patreon_user, actor: actor)
      end
    end

    # https://github.com/github/sponsors/issues/5337
    test "no-op when SponsorsPatreonUser is for an account whose SponsorsListing is not approved" do
      non_sponsorable_patreon_user = create(:sponsors_patreon_user, :sponsor)
      actor = non_sponsorable_patreon_user.user
      create(:sponsors_listing, :draft, sponsorable: actor)

      CreateAndUpdatePatreonSponsorships.expects(:call).never
      CancelPatreonSponsorships.expects(:call).never

      assert_no_enqueued_jobs(only: SyncPatreonSponsorshipsJob) do
        SyncPatreonSponsorshipsJob.perform_now(non_sponsorable_patreon_user, actor: actor)
      end
    end
  else
    test "no-op if GitHub Sponsors is not enabled" do
      sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
      actor = sponsor_spu.user

      CreateAndUpdatePatreonSponsorships.expects(:call).never
      CancelPatreonSponsorships.expects(:call).never

      assert_no_enqueued_jobs(only: SyncPatreonSponsorshipsJob) do
        SyncPatreonSponsorshipsJob.perform_now(@spu, actor: actor, max_membership_pages: 1,
          membership_page_cursors_by_campaign_id: { "459978" => "02B9AS9r0rVy7smJCVpWQPdNob" })
      end
    end
  end
end
