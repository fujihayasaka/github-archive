# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Repositioner
      # Request object for the given position. As the position changes over time, we capture
      # multiple versions depending on side effects of git operations. The more positional data
      # the more likely we can reuse some of the data points, reducing GitRPC calls.
      class Request < T::Struct
        const :identifier, Integer

        # Positioning this record was created with.
        const :original_positioning, Positions

        # Positioning this record is currently targeting. Force pushes and history rewrites forces
        # positions targeting the now moved base sha must be positioned to a new base sha.
        const :base_positioning, T.nilable(Positions)

        # The most recent positioning based on the base/head of the Pull Request.
        const :head_positioning, T.nilable(Positions)

        sig { returns(T::Array[Positions]) }
        def available_positionings
          [original_positioning, base_positioning, head_positioning].compact
        end
      end
    end
  end
end
