# frozen_string_literal: true

class RepositoryPushProcessor < ApplicationProcessor
  group_name "repository_push"
  handle_topic(/github\.v1\.RepositoryPush\Z/, RepositoryPushHandler)

  def initialize
    # This processor has issues with completing larger batches within the session_timeout
    options[:session_timeout] = 5.minutes
  end
end
