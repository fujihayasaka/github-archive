# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Processors
        Types = T.type_alias do
          T.any(
            Processors::DiffRelative,
            Processors::Blobs,
            Processors::Positioning,
            Processors::ThreadColumns,
            Processors::Repositioning
          )
        end
      end
    end
  end
end
