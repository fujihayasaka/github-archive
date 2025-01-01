# typed: true
# frozen_string_literal: true

class Actions::WorkflowRun::Resources < Permissions::FineGrainedResource
  # Internal: Which workflow run resources can an OauthAuthorization be
  # granted permission on. These are all internal resources.
  SUBJECT_TYPES = GitHub.fine_grained_resources["workflow_run"].keys.freeze

  ABILITY_TYPE_PREFIX = "WorkflowRun"

  WRITEONLY_SUBJECT_TYPES = GitHub.writeonly_fine_grained_resources("workflow_run").freeze
end
