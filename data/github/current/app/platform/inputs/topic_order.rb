# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class TopicOrder < Platform::Inputs::Base
      description "Ordering options for topic connections."
      visibility :internal

      argument :field, Enums::TopicOrderField, "The field to order topics by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
