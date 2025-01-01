# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorableOrderField < Platform::Enums::Base
      description "Properties by which sponsorable connections can be ordered."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "LOGIN", "Order sponsorable entities by login (username).", value: "login"
    end
  end
end
