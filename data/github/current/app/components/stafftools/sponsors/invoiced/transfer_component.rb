# typed: strict
# frozen_string_literal: true

module Stafftools
  module Sponsors
    module Invoiced
      class TransferComponent < ApplicationComponent
        # is_even_row - whether this is an evenly numbered row in the table of all transfers
        sig do
          params(transfer: InvoicedSponsorshipTransfer, sponsor: ::Organization, is_even_row: T::Boolean).void
        end
        def initialize(transfer:, sponsor:, is_even_row: false)
          @transfer = transfer
          @sponsor = sponsor
          @is_even_row = is_even_row
        end

        private

        sig { returns InvoicedSponsorshipTransfer }
        attr_reader :transfer

        sig { returns ::Organization }
        attr_reader :sponsor

        delegate :sponsorship, :reversals, :sponsorable, to: :transfer

        sig { returns T::Boolean }
        def render?
          transfer.sponsor_id == sponsor.id && logged_in? && GitHub.sponsors_enabled?
        end

        sig { returns T::Boolean }
        def even_row?
          @is_even_row
        end

        sig { returns ::User }
        memoize def actor
          transfer.actor || ::User.ghost
        end
      end
    end
  end
end
