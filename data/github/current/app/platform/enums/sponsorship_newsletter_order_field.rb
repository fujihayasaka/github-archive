# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorshipNewsletterOrderField < Platform::Enums::Base
      description "Properties by which sponsorship update connections can be ordered."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "CREATED_AT", "Order sponsorship newsletters by when they were created.", value: "created_at"
    end
  end
end
