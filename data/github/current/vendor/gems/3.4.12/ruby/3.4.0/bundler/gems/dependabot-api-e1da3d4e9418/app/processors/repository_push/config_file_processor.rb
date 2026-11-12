# frozen_string_literal: true

module RepositoryPush
  class ConfigFileProcessor < ApplicationProcessor
    group_name "repository_push_config_file"
    handle_topic(/github\.v1\.RepositoryPush\Z/, ConfigFileHandler)
  end
end
