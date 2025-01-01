# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class TeamDiscussionOrder < Platform::Inputs::Base
      description "Ways in which team discussion connections can be ordered."

      argument :field, Enums::TeamDiscussionOrderField, "The field by which to order nodes.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order nodes.", required: true
    end
  end
end
