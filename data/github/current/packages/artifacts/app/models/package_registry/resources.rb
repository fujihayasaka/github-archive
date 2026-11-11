# typed: true
# frozen_string_literal: true

module PackageRegistry
  class Resources < Permissions::FineGrainedResource
    SUBJECT_TYPES = GitHub.fine_grained_resources["package_registry"].keys.freeze

    ABILITY_TYPE_PREFIX = "Package"
  end
end
