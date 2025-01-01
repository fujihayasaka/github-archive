# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DeploymentOrder < Platform::Inputs::Base
      description "Ordering options for deployment connections"

      argument :field, Enums::DeploymentOrderField, "The field to order deployments by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
