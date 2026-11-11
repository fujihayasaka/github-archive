# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamPrivacy < Platform::Enums::Base
      description "The possible team privacy values."

      value "SECRET", "A secret team can only be seen by its members.", value: "secret"
      value "VISIBLE", "A visible team can be seen and @mentioned by every member of the organization.", value: "closed"
    end
  end
end
