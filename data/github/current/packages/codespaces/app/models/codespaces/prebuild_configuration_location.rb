# typed: true
# frozen_string_literal: true

module Codespaces
  class PrebuildConfigurationLocation < ApplicationRecord::Domain::Codespaces
    self.table_name = "codespace_prebuild_configuration_locations"

    include Instrumentation::Model

    ALL_LOCATIONS = "all_locations"
    SPECIFIC_LOCATIONS = "specific_locations"

    validates :codespace_prebuild_configuration_id, uniqueness: { scope: :location }

    belongs_to :configuration, class_name: "Codespaces::PrebuildConfiguration"

    enum :location, {
      "EastUs" => 0,
      "SouthEastAsia" => 1,
      "WestEurope" => 2,
      "WestUs2" => 3,
      "AustraliaEast" => 4,
      "EastUs2" => 5,
      "UkSouth" => 6,
      "WestUs3" => 7,
      "CentralIndia" => 8,
      "AustraliaCentral" => 9,
    }

    enum :geo, {
      "UsEast" => 0,
      "UsWest" => 1,
      "EuropeWest" => 2,
      "SoutheastAsia" => 3,
      "Australia" => 4,
    }
  end
end
