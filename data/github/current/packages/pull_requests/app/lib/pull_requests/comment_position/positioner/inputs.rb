# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Inputs
        Types = T.type_alias do
          T.any(
            Positioning,
            DiffRelative,
            Blobs,
            ThreadColumns
          )
        end
      end
    end
  end
end
