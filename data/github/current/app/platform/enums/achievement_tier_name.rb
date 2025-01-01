# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AchievementTierName < Platform::Enums::Base
      description "Metallic-color names describing the unlockable levels of an Achievable."

      mobile_only true

      value "DEFAULT", "First or only tier.", value: 0
      value "BRONZE", "Second tier.", value: 1
      value "SILVER", "Third tier.", value: 2
      value "GOLD", "Fourth tier.", value: 3
      value "CRYSTAL", "Fifth tier.", value: 4
    end
  end
end
