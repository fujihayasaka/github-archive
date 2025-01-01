# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorsActivityOrderField < Platform::Enums::Base
      description "Properties by which GitHub Sponsors activity connections can be ordered."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "TIMESTAMP", "Order activities by when they happened.", value: "timestamp"
    end
  end
end
