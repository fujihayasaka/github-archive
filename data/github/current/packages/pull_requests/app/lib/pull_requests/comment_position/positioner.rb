# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      Values = T.type_alias { T.any(Result, Errors) }
    end
  end
end
