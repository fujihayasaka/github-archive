# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class FundingPlatform < Platform::Enums::Base
      description "The possible funding platforms for repository funding links."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      FundingPlatforms::ALL.values.each do |platform|
        value self.convert_string_to_enum_value(platform.key.to_s),
          "#{platform.name} funding platform.",
          value: platform.key
      end
    end
  end
end
