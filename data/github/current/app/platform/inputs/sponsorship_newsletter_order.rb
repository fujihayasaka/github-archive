# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class SponsorshipNewsletterOrder < Platform::Inputs::Base
      docs_category :sponsors
      description "Ordering options for sponsorship newsletter connections."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      argument :field, Enums::SponsorshipNewsletterOrderField,
        "The field to order sponsorship newsletters by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
