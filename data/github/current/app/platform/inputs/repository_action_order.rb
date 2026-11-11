# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class RepositoryActionOrder < Platform::Inputs::Base
      description "Ordering options for repository action connections."
      visibility :internal

      argument :field, Enums::RepositoryActionOrderField, "The field to order topics by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
