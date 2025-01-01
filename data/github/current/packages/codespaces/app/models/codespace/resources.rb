# typed: true
# frozen_string_literal: true

class Codespace
  class Resources < Permissions::FineGrainedResource
    PRIVATE_SUBJECT_TYPES = %w(codespace_metadata)
    SUBJECT_TYPES = PRIVATE_SUBJECT_TYPES

    ABILITY_TYPE_PREFIX = "Codespace"

    READONLY_SUBJECT_TYPES = %w(codespace_metadata)
  end
end
