# frozen_string_literal: true

module RepositoryPush
  class ConfigFileProcessor < ApplicationProcessor
    group_name "repository_push_config_file"
    handle_topic(/github\.v1\.RepositoryPush\Z/, ConfigFileHandler)

    def initialize
      # This processor can receive very large payloads, where the default
      # 5kb min_bytes may result in small batches being fetched from
      # hydro too frequently and resulting in the consumer being I/O bound.
      options[:min_bytes] = 20.kilobytes
    end
  end
end
