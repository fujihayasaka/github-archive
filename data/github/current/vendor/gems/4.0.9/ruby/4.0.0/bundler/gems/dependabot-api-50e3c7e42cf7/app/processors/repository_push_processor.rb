# frozen_string_literal: true

class RepositoryPushProcessor < ApplicationProcessor
  group_name "repository_push"
  handle_topic(/github\.v1\.RepositoryPush\Z/, RepositoryPushHandler)

  def initialize
    # This processor has issues with completing larger batches within the session_timeout
    options[:session_timeout] = 5.minutes

    # This processor can receive very large payloads, where the default
    # 5kb min_bytes may result in small batches being fetched from
    # hydro too frequently and resulting in the consumer being I/O bound.
    options[:min_bytes] = 20.kilobytes
  end
end
