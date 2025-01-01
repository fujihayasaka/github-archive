# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class RepositoryOrder < Platform::Inputs::Base
      description "Ordering options for repository connections"

      argument :field, Enums::RepositoryOrderField, "The field to order repositories by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
