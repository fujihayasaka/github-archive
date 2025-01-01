# typed: strict
# frozen_string_literal: true

module Stafftools
  module Sponsors
    module Invoiced
      class TransferReversalComponent < ApplicationComponent
        # is_last - whether this is the last reversal in the list of all reversals for the transfer
        # cell_classes - optional CSS classes to apply to each table cell in the row
        sig do
          params(
            transfer: InvoicedSponsorshipTransfer,
            reversal: InvoicedSponsorshipTransferReversal,
            is_last: T::Boolean,
            cell_classes: T.nilable(String)
          ).void
        end
        def initialize(transfer:, reversal:, is_last: false, cell_classes: "color-bg-inset")
          @transfer = transfer
          @reversal = reversal
          @is_last = is_last
          @cell_classes = cell_classes
        end

        private

        sig { returns InvoicedSponsorshipTransfer }
        attr_reader :transfer

        sig { returns InvoicedSponsorshipTransferReversal }
        attr_reader :reversal

        sig { returns T.nilable(String) }
        attr_reader :cell_classes

        sig { returns T::Boolean }
        def render?
          reversal.invoiced_sponsorship_transfer_id == transfer.id && logged_in? && GitHub.sponsors_enabled?
        end

        sig { returns T::Boolean }
        def last?
          @is_last
        end

        sig { returns ::User }
        memoize def actor
          reversal.actor || ::User.ghost
        end
      end
    end
  end
end
