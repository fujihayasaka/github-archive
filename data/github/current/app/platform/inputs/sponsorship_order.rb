# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SponsorshipOrder < Platform::Inputs::Base
      description "Ordering options for sponsorship connections."

      argument :field, Enums::SponsorshipOrderField,
        "The field to order sponsorship by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
