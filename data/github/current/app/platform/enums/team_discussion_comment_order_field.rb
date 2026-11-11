# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamDiscussionCommentOrderField < Platform::Enums::Base
      description "Properties by which team discussion comment connections can be ordered."

      value(
        "NUMBER",
        "Allows sequential ordering of team discussion comments (which is equivalent to " +
          "chronological ordering).",
        value: "number")
    end
  end
end
