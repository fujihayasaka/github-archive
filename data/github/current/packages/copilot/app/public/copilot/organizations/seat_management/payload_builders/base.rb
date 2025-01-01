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
            return nil unless seat_detail.assignable.present?

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
              assignable_type: assignable.class.to_s,
              pending_cancellation_date: seat_detail.pending_cancellation_date&.to_date,
              last_activity_at: seat_detail.last_activity_at,
              invitation_date: nil,
              invitation_expired: nil,
              assignable: {
                id: assignable.id,
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

          sig { returns(T.any(::User, ::Team, ::OrganizationInvitation, ::Organization)) }
          memoize def assignable
            # This is only okay because of our early return in #call
            T.must(seat_detail.assignable)
          end
        end
      end
    end
  end
end
