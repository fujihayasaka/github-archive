# typed: strict
# frozen_string_literal: true

module TradeControls
  module Sdn
    class EnableOrDisableMaintainerJob < ApplicationJob

      queue_as :trade_screening
      retry_on_dirty_exit

      sig { params(id: Integer).void }
      def perform(id)
        personal_profile = AccountScreeningProfile.find_by(id: id)
        listing = personal_profile&.sponsors_listing
        unless listing
          GitHub.logger.error("Unable to find sponsors_listing for toggling maintainer", "gh.account_screening_profile.id": id)
          return
        end

        listing_can_be_disabled = listing.approved? && !listing.sdn_disabled?
        if personal_profile.blocked_status_for_sponsorship_disable? && listing_can_be_disabled
          with_write { listing.sdn_disable! }
        elsif listing.sdn_disabled? && !personal_profile.true_match?
          with_write { listing.sdn_enable! }
        end
      end
    end
  end
end
