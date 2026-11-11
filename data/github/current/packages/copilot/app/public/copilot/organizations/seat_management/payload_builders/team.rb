# typed: strict
# frozen_string_literal: true

module Copilot
  module Organizations
    module SeatManagement
      module PayloadBuilders
        class Team < Copilot::Organizations::SeatManagement::PayloadBuilders::Base
          private

          sig { override.void }
          def transform_payload!
            seat_payload[:assignable].merge!({
              id: team.id,
              login: team.name || "",
              slug: team.slug || "",
              avatar_url: T.cast(avatar_url_for(team, 48), String),
              combined_slug: team.combined_slug,
              member_count: team.members_count,
              member_ids: team.member_ids
            })
          end

          sig { returns(::Team) }
          def team
            T.cast(assignable, ::Team)
          end
        end
      end
    end
  end
end
