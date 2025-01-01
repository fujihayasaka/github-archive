# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Codespaces
      autoload :ComputeUsageProcessor, "github/stream_processors/codespaces/compute_usage_processor"
      autoload :StorageUsageProcessor, "github/stream_processors/codespaces/storage_usage_processor"
    end
  end
end
