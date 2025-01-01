# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class Environments < Platform::Inputs::Base
      description "Ordering options for environments"

      argument :field, Enums::EnvironmentOrderField, "The field to order environments by.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order environments by the specified field.", required: true
    end
  end
end
