# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module SeatManagement
      module PayloadBuilders
        class Null < Copilot::Organizations::SeatManagement::PayloadBuilders::Base
          private

          sig { override.void }
          def transform_payload!
            seat_payload[:assignable].merge!({
              id: 0,
              display_name: nil,
              login: nil,
              avatar_url: T.cast(avatar_url_for(::User.ghost, 96), String)
            })
          end
        end
      end
    end
  end
end
