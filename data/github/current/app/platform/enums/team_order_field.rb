# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamOrderField < Platform::Enums::Base
      description "Properties by which team connections can be ordered."

      value "NAME", "Allows ordering a list of teams by name.", value: "name"
    end
  end
end
