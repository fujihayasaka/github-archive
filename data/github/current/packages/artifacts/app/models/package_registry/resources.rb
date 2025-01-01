# typed: true
# frozen_string_literal: true

module PackageRegistry
  class Resources < Permissions::FineGrainedResource
    SUBJECT_TYPES = %w(
      administration
      contents
      maintainer
    ).freeze

    ABILITY_TYPE_PREFIX = "Package"
  end
end
