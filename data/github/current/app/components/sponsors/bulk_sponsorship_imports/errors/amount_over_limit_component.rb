# typed: strict
# frozen_string_literal: true

module Sponsors
  module BulkSponsorshipImports
    module Errors
      class AmountOverLimitComponent < ApplicationComponent
        extend T::Sig
        include Sponsors::BulkSponsorshipImports::Errors::ViewComponentMethods

        private

        sig { override.returns(String) }
        def test_selector
          "amount-over-limit-error"
        end

        sig { override.returns(String) }
        def error_message
          noun = sponsorable_logins_count == 1 ? "maintainer" : "#{sponsorable_logins_count} maintainers"
          "You cannot sponsor the following #{noun} because each amount exceeds the " \
            "sponsorship limit of #{SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN}:"
        end
      end
    end
  end
end
