# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorshipOrderField < Platform::Enums::Base
      description "Properties by which sponsorship connections can be ordered."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "CREATED_AT", "Order sponsorship by creation time.", value: "created_at"
    end
  end
end
