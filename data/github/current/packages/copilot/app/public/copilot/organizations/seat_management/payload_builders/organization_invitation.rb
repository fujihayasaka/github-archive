# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module SeatManagement
      module PayloadBuilders
        class OrganizationInvitation < Copilot::Organizations::SeatManagement::PayloadBuilders::Base
          private

          sig { override.void }
          def transform_payload!
            seat_payload[:assignable].merge!({
              id: invite.id,
              email: invite.email
            })
            seat_payload[:invitation_date] = invite.created_at
            seat_payload[:invitation_expired] = invite.expired?
            if invite.invitee.present?
              user = T.cast(invite.invitee, ::User)
              seat_payload[:assignable].merge!({
                display_name: user.profile_name,
                login: user.display_login,
                avatar_url: T.cast(avatar_url_for(user, 96), String)
              })
              seat_payload[:assignable][:invitee] = {
                id: user.id,
                display_name: user.profile_name,
                login: user.display_login,
                avatar_url: T.cast(avatar_url_for(user, 96), String)
              }
            end
          end

          sig { returns(::OrganizationInvitation) }
          def invite
            T.cast(assignable, ::OrganizationInvitation)
          end
        end
      end
    end
  end
end
