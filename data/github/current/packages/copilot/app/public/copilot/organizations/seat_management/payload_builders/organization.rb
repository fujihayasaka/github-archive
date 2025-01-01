# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module SeatManagement
      module PayloadBuilders
        class Organization < Copilot::Organizations::SeatManagement::PayloadBuilders::User
          private

          sig { returns(::User) }
          def user
            seat_detail.assigned_user
          end
        end
      end
    end
  end
end
