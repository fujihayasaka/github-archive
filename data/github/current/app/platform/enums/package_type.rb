# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PackageType < Platform::Enums::Base
      description "The possible types of a package."

      value "NPM", "An npm package.", value: "npm", deprecated: {
        reason: "NPM will be removed from this enum as this type will be migrated to only be used by the Packages REST API.",
        superseded_by: nil,
        start_date: Date.new(2022, 11, 21),
        override_sunset_date: Date.new(2022, 11, 21),
        owner: "s-anupam",
      }
      value "RUBYGEMS", "A rubygems package.", value: "rubygems", deprecated: {
        reason: "RUBYGEMS will be removed from this enum as this type will be migrated to only be used by the Packages REST API.",
        superseded_by: nil,
        start_date: Date.new(2022, 12, 28),
        override_sunset_date: Date.new(2022, 12, 28),
        owner: "ankitkaushal01",
      }
      value "MAVEN", "A maven package.", value: "maven", deprecated: {
        reason: "MAVEN will be removed from this enum as this type will be migrated to only be used by the Packages REST API.",
        superseded_by: nil,
        start_date: Date.new(2023, 02, 10),
        override_sunset_date: Date.new(2023, 02, 10),
        owner: "ankitkaushal01",
      }
      value "DOCKER", "A docker image.", value: "docker", deprecated: {
        reason: "DOCKER will be removed from this enum as this type will be migrated to only be used by the Packages REST API.",
        superseded_by: nil,
        start_date: Date.new(2021, 6, 21),
        override_sunset_date: Date.new(2021, 6, 21),
        owner: "reybard",
      }
      value "DEBIAN", "A debian package.", value: "debian"
      value "NUGET", "A nuget package.", value: "nuget", deprecated: {
        reason: "NUGET will be removed from this enum as this type will be migrated to only be used by the Packages REST API.",
        superseded_by: nil,
        start_date: Date.new(2022, 11, 21),
        override_sunset_date: Date.new(2022, 11, 21),
        owner: "s-anupam",
      }
      value "PYPI", "A python package.", value: "python"
    end
  end
end
