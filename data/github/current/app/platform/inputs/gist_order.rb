# typed: strict
# frozen_string_literal: true

module Platform
  module Inputs
    class GistOrder < Platform::Inputs::Base
      description "Ordering options for gist connections"

      argument :field, Enums::GistOrderField, "The field to order repositories by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
