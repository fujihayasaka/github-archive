# typed: true
# frozen_string_literal: true

require "test_helper"

class SendPendingSponsorshipEmailJobTest < GitHub::TestCase
  fixtures do
    @sponsorship = create(:sponsorship)
    @pending_sponsorship = create(:sponsorship, :pending)
  end

  if GitHub.sponsors_enabled?
    test "sends pending email when the sponsorship has a pending state and when FF is enabled" do
      enable_feature_flag(:sponsors_pending_sponsorships, @pending_sponsorship.sponsor)

      SponsorsPrimerMailer.expects(:new_sponsor).never
      SponsorsPrimerMailer.expects(:now_sponsoring).never
      SponsorsPrimerMailer.expects(:pending_sponsorship).once.with(
        sponsorable: @pending_sponsorship.sponsorable,
        sponsor: @pending_sponsorship.sponsor,
        sponsorship_amount: @pending_sponsorship.amount_per_cycle
      ).returns(stub(deliver_later: nil))

      SendPendingSponsorshipEmailJob.perform_now(@pending_sponsorship)
    end

    test "does not send pending email when the sponsorship has a pending state but FF is disabled" do
      disable_feature_flag(:sponsors_pending_sponsorships)

      SponsorsPrimerMailer.expects(:new_sponsor).never
      SponsorsPrimerMailer.expects(:now_sponsoring).never
      SponsorsPrimerMailer.expects(:pending_sponsorship).never

      SendPendingSponsorshipEmailJob.perform_now(@pending_sponsorship)
    end

    test "does not send pending email when the sponsorship has a non-pending state when FF is enabled" do
      enable_feature_flag(:sponsors_pending_sponsorships, @sponsorship.sponsor)

      SponsorsPrimerMailer.expects(:new_sponsor).never
      SponsorsPrimerMailer.expects(:now_sponsoring).never
      SponsorsPrimerMailer.expects(:pending_sponsorship).never

      SendPendingSponsorshipEmailJob.perform_now(@sponsorship)
    end
  end
end
