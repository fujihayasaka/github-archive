# typed: strict
# frozen_string_literal: true

module Stafftools
  module Sponsors
    module Invoiced
      class TransfersListComponent < ApplicationComponent
        extend T::Sig

        # sponsor - the Organization the transfers are from
        sig do
          params(transfers: T.any(WillPaginate::Collection, ActiveRecord::Relation), sponsor: ::Organization).void
        end
        def initialize(transfers:, sponsor:)
          @transfers = transfers
          @sponsor = sponsor
        end

        private

        sig { returns ::Organization }
        attr_reader :sponsor

        sig { returns T::Boolean }
        def render?
          logged_in? && GitHub.sponsors_enabled?
        end

        sig { returns T.any(WillPaginate::Collection, ActiveRecord::Relation) }
        memoize def transfers
          GitHub::PrefillAssociations.prefill_associations(@transfers, [:sponsorship, :reversals])

          transfers_and_reversals = @transfers + @transfers.flat_map(&:reversals)
          known_users = [sponsor, current_user]
          user_ids_to_look_up = (
            transfers_and_reversals.map(&:actor_id) + @transfers.map(&:sponsorable_id)
          ).compact.to_set - known_users.map(&:id).to_set
          known_users += ::User.where(id: user_ids_to_look_up).to_a

          GitHub::PrefillAssociations.prefill_associations(@transfers, :sponsorable, available_records: known_users)
          GitHub::PrefillAssociations.prefill_associations(transfers_and_reversals, :actor,
            available_records: known_users)

          @transfers
        end
      end
    end
  end
end
