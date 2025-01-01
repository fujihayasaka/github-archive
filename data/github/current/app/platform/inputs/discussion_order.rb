# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DiscussionOrder < Platform::Inputs::Base
      description "Ways in which lists of discussions can be ordered upon return."

      argument :field, Enums::DiscussionOrderField, "The field by which to order discussions.",
        required: true
      argument :direction, Enums::OrderDirection,
        "The direction in which to order discussions by the specified field.", required: true
    end
  end
end
