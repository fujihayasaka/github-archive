# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module SponsorsActivity
      autoload :SponsorshipCancelProcessor, "github/stream_processors/sponsors_activity/sponsorship_cancel_processor"
      autoload :SponsorshipPaymentCompleteProcessor, "github/stream_processors/sponsors_activity/sponsorship_payment_complete_processor"
      autoload :SponsorshipPendingChangeProcessor, "github/stream_processors/sponsors_activity/sponsorship_pending_change_processor"
      autoload :SponsorshipTierChangeProcessor, "github/stream_processors/sponsors_activity/sponsorship_tier_change_processor"
      autoload :SponsorshipTransferReversalProcessor, "github/stream_processors/sponsors_activity/sponsorship_transfer_reversal_processor"
    end
  end
end
