# typed: true
# frozen_string_literal: true

class ProtectedBranch::Resources < Permissions::FineGrainedResource
  # Internal: Which protected branch resources are publicly available.
  PUBLIC_SUBJECT_TYPES = GitHub.public_fine_grained_resources("protected_branch").freeze

  # Internal: Which protected branch resources can an IntegrationInstallation
  # be granted permission on.
  SUBJECT_TYPES = PUBLIC_SUBJECT_TYPES

  ABILITY_TYPE_PREFIX = "ProtectedBranch"
end
