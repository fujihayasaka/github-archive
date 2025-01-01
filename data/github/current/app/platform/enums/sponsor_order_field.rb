# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorOrderField < Platform::Enums::Base
      description "Properties by which sponsor connections can be ordered."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "LOGIN", "Order sponsorable entities by login (username).", value: "login"
      value "RELEVANCE", "Order sponsors by their relevance to the viewer.", value: "relevance"
    end
  end
end
