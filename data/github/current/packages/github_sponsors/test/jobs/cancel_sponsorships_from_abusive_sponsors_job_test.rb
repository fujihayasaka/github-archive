# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CancelSponsorshipsFromAbusiveSponsorsJobTest < GitHub::TestCase
  include AuditLogHelpers
  include JobTestHelper
  include HydroTestHelpers
  include GitHub::SponsorsInstrumentationTestHelpers

  fixtures do
    @sponsorship_from_spammer = create(:sponsorship)
    @spammer = @sponsorship_from_spammer.sponsor
    @sponsorship_from_suspended_user = create(:sponsorship)
    @suspended_user = @sponsorship_from_suspended_user.sponsor
    @cutoff_time = (CancelSponsorshipsFromAbusiveSponsorsJob::GRACE_PERIOD_IN_DAYS + 1).
      days.ago.freeze
  end

  setup do
    mark_spammy_at(@spammer, @cutoff_time)
    mark_suspended_at(@suspended_user, @cutoff_time)
  end

  def mark_spammy_at(user, time)
    travel_to(time) do
      with_es_refresh { perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { user.mark_as_spammy } }
    end
  end

  def mark_suspended_at(user, time)
    travel_to(time) do
      with_es_refresh { user.suspend("bad actor") }
    end
  end

  if GitHub.sponsors_enabled? && GitHub.spamminess_check_enabled?
    test "cancels non-invoiced sponsorship and its subscription item from spammy sponsor" do
      CancelSponsorshipsFromAbusiveSponsorsJob.perform_now

      refute_predicate @sponsorship_from_spammer.reload, :active?
      refute_predicate @sponsorship_from_spammer.reload_subscription_item, :active?
    end

    test "cancels non-invoiced sponsorship and its subscription item from suspended sponsor" do
      CancelSponsorshipsFromAbusiveSponsorsJob.perform_now

      refute_predicate @sponsorship_from_suspended_user.reload, :active?
      refute_predicate @sponsorship_from_suspended_user.reload_subscription_item, :active?
    end

    test "does not cancel non-invoiced sponsorships and its subscription item from spammy sponsor under cutoff time" do
      sponsorship = create(:sponsorship)
      suspended_user = sponsorship.sponsor
      mark_suspended_at(suspended_user, @cutoff_time + 2.days)

      CancelSponsorshipsFromAbusiveSponsorsJob.perform_now

      assert_predicate sponsorship.reload, :active?
      assert_predicate sponsorship.reload_subscription_item, :active?
    end

    test "cancels non-invoiced sponsorship and its subscription item for a sponsor that is both spammy and suspended" do
      sponsorship = create(:sponsorship)
      spammy_suspended_user = sponsorship.sponsor
      mark_suspended_at(spammy_suspended_user, @cutoff_time)
      mark_spammy_at(spammy_suspended_user, @cutoff_time)

      CancelSponsorshipsFromAbusiveSponsorsJob.perform_now

      refute_predicate sponsorship.reload, :active?
      refute_predicate sponsorship.reload_subscription_item, :active?
    end

    test "cancels sponsorships from spammy sponsors when there is more than one batch" do
      sponsorship2 = create(:sponsorship)
      spammer2 = sponsorship2.sponsor
      mark_spammy_at(spammer2, @cutoff_time)

      CancelSponsorshipsFromAbusiveSponsorsJob.stub_const(:BATCH_SIZE, 1) do
        CancelSponsorshipsFromAbusiveSponsorsJob.perform_now

        refute_predicate @sponsorship_from_spammer.reload, :active?
        refute_predicate @sponsorship_from_spammer.reload_subscription_item, :active?
        refute_predicate sponsorship2.reload, :active?
        refute_predicate sponsorship2.reload_subscription_item, :active?
      end
    end

    test "reports failures across all batches" do
      sponsorship2 = create(:sponsorship)
      spammer2 = sponsorship2.sponsor
      mark_spammy_at(spammer2, @cutoff_time)
      Sponsorship.any_instance.stubs(:cancel).returns(Billing::Public::ResultStruct.new(success: false))

      CancelSponsorshipsFromAbusiveSponsorsJob.stub_const(:BATCH_SIZE, 1) do
        error = assert_raises(RuntimeError) do
          CancelSponsorshipsFromAbusiveSponsorsJob.perform_now
        end

        assert_equal "Failed to cancel 3 sponsorships from 3 spammy or suspended sponsors", error.message
      end
    end

    test "cancels non-Zuora invoiced sponsorship from spammy sponsor" do
      invoiced_sponsorship = create(:sponsorship, :invoiced, expires_at: nil)
      spammer = invoiced_sponsorship.sponsor
      mark_spammy_at(spammer, @cutoff_time)

      CancelSponsorshipsFromAbusiveSponsorsJob.perform_now

      refute_predicate invoiced_sponsorship.reload, :active?
      refute_nil invoiced_sponsorship.expires_at
    end

    test "cancels Zuora invoiced sponsorship from spammy sponsor" do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      sponsorship = create(:sponsorship, sponsor: invoiced_org)
      assert_equal invoiced_org.sponsors_plan_subscription, sponsorship.plan_subscription
      mark_spammy_at(invoiced_org, @cutoff_time)

      CancelSponsorshipsFromAbusiveSponsorsJob.perform_now

      refute_predicate sponsorship.reload, :active?
      refute_predicate sponsorship.reload_subscription_item, :active?
    end

    test "instruments sponsorship cancellation request to Hydro" do
      CancelSponsorshipsFromAbusiveSponsorsJob.perform_now

      assert_sponsorship_cancel_request_hydro_published(
        sponsorship: @sponsorship_from_spammer,
        reason: :SPAMMY_SPONSOR,
        actor: nil,
      )
      assert_sponsorship_cancel_request_hydro_published(
        sponsorship: @sponsorship_from_suspended_user,
        reason: :SPAMMY_SPONSOR,
        actor: nil,
      )
      assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end

    test "raises exception when any of the sponsorships fail to cancel" do
      Sponsorship.any_instance.stubs(:cancel).returns(Billing::Public::ResultStruct.new(success: false))

      error = assert_raises(RuntimeError) do
        CancelSponsorshipsFromAbusiveSponsorsJob.perform_now
      end

      assert_equal "Failed to cancel 2 sponsorships from 2 spammy or suspended sponsors", error.message
    end

    test "no-op when spammy sponsor has no active sponsorships" do
      inactive_sponsorship = create(:sponsorship, :inactive)
      spammer = inactive_sponsorship.sponsor
      mark_spammy_at(spammer, @cutoff_time)

      CancelSponsorshipsFromAbusiveSponsorsJob.perform_now

      refute_predicate inactive_sponsorship.reload, :active?
      refute_predicate inactive_sponsorship.reload_subscription_item, :active?
    end

    test "no-op when sponsor is not spammy" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { @spammer.mark_as_hammy }

      CancelSponsorshipsFromAbusiveSponsorsJob.perform_now

      assert_predicate @sponsorship_from_spammer.reload, :active?
      assert_predicate @sponsorship_from_spammer.reload_subscription_item, :active?
    end

    test "no-op when sponsor was recently marked spammy" do
      with_es_refresh do
        log(action: "staff.mark_as_spammy", user_id: @spammer.id, created_at: 1.hour.ago)
      end

      CancelSponsorshipsFromAbusiveSponsorsJob.perform_now

      assert_predicate @sponsorship_from_spammer.reload, :active?
      assert_predicate @sponsorship_from_spammer.reload_subscription_item, :active?
    end

    test "retries the job on dirty exit" do
      assert_retry_on_dirty_exit(job: CancelSponsorshipsFromAbusiveSponsorsJob)
    end
  end
end
