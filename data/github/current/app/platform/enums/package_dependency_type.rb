# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PackageDependencyType < Platform::Enums::Base
      description "The possible types of a package dependency."

      visibility :internal

      value "DEFAULT", "A default package dependency type.", value: "default"
      value "DEV", "A dev package dependency type.", value: "dev"
      value "TEST", "A test package dependency type.", value: "test"
      value "PEER", "A peer package dependency type.", value: "peer"
      value "OPTIONAL", "An optional package dependency type.", value: "optional"
      value "BUNDLED", "An optional package dependency type.", value: "bundled"
    end
  end
end
