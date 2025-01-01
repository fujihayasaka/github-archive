# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module SeatManagement
      module PayloadBuilders
        class Base
          extend T::Helpers
          include GitHub::Memoizer
          include AvatarHelper

          abstract!

          sig { returns(Copilot::Organizations::SeatManagement::Detail) }
          attr_reader :seat_detail

          sig { params(seat_detail: Copilot::Organizations::SeatManagement::Detail).void }
          def initialize(seat_detail:)
            @seat_detail = seat_detail
          end

          sig { returns(T.nilable(Copilot::Types::SeatPayload)) }
          def call
            if !seat_detail.assignable.present?
              return nil unless seat_detail.seat_assignment.access_revoked?
            end

            transform_payload!

            seat_payload
          end

          private

          sig { returns(Copilot::Types::SeatPayload) }
          memoize def seat_payload
            default_value
          end

          sig { returns(Copilot::Types::SeatPayload) }
          def default_value
            {
              assignable_type: T.cast(seat_detail.seat_assignment.assignable_type, String),
              pending_cancellation_date: seat_detail.pending_cancellation_date&.to_date || seat_detail.seat_assignment.pending_cancellation_date&.to_date,
              access_revoked_at: seat_detail.access_revoked_at&.to_date || seat_detail.seat_assignment.access_revoked_at&.to_date,
              last_activity_at: seat_detail.last_activity_at,
              invitation_date: nil,
              invitation_expired: nil,
              assignable: {
                id: T.cast(seat_detail.seat_assignment.assignable_id, Integer),
                login: nil,
                avatar_url: nil,
                display_name: nil,
                slug: nil,
                combined_slug: nil,
                member_count: nil,
                member_ids: nil,
                email: nil,
                invitee: nil,
              },
            }
          end

          sig { abstract.void }
          def transform_payload!; end

          sig { returns(T.nilable(T.any(::User, ::Team, ::OrganizationInvitation, ::Organization))) }
          memoize def assignable
            seat_detail.assignable
          end
        end
      end
    end
  end
end
