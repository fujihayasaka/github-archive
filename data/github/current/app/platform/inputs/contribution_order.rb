# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ContributionOrder < Platform::Inputs::Base
      description "Ordering options for contribution connections."

      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
