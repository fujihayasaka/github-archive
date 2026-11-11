# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module SeatManagement
      module PayloadBuilders
        class User < Copilot::Organizations::SeatManagement::PayloadBuilders::Base
          private

          sig { override.void }
          def transform_payload!
            seat_payload[:assignable].merge!({
              id: user.id,
              display_name: user.profile_name,
              login: user.display_login,
              avatar_url: user.nil? || !user.persisted? ? nil : T.cast(avatar_url_for(user, 96), String)
            })
          end

          sig { returns(::User) }
          def user
            T.cast(assignable, ::User)
          end
        end
      end
    end
  end
end
