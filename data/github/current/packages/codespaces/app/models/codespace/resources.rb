# typed: true
# frozen_string_literal: true

class Codespace
  class Resources < Permissions::FineGrainedResource
    PRIVATE_SUBJECT_TYPES = GitHub.private_fine_grained_resources("codespace")
    SUBJECT_TYPES = PRIVATE_SUBJECT_TYPES

    ABILITY_TYPE_PREFIX = "Codespace"

    READONLY_SUBJECT_TYPES = GitHub.readonly_fine_grained_resources("codespace")
  end
end
