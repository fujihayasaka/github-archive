# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CommitContributionOrder < Platform::Inputs::Base
      description "Ordering options for commit contribution connections."

      argument :field, Enums::CommitContributionOrderField,
        "The field by which to order commit contributions.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
