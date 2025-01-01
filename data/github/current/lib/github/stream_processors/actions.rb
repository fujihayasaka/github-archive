# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Actions
      autoload :ArtifactStorageEventProcessor, "github/stream_processors/actions/artifact_storage_event_processor"
      autoload :RepositoryUsageProcessor, "github/stream_processors/actions/repository_usage_processor"
      autoload :DisableWorkflowProcessor, "github/stream_processors/actions/disable_workflow_processor"
      autoload :ReputationScoreChangeEventProcessor, "github/stream_processors/actions/reputation_score_change_event_processor"
    end
  end
end
