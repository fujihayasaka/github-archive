# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DiscussionPollOptionOrder < Platform::Inputs::Base
      description "Ordering options for discussion poll option connections."

      visibility :public, environments: [:dotcom, :enterprise]

      argument :field, Enums::DiscussionPollOptionOrderField, "The field to order poll options by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
