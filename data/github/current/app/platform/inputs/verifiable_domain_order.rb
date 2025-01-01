# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class VerifiableDomainOrder < Platform::Inputs::Base
      description "Ordering options for verifiable domain connections."

      argument :field, Enums::VerifiableDomainOrderField, "The field to order verifiable domains by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
