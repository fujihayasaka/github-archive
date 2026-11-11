# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class MilestoneOrder < Platform::Inputs::Base
      description "Ordering options for milestone connections."

      argument :field, Enums::MilestoneOrderField, "The field to order milestones by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
