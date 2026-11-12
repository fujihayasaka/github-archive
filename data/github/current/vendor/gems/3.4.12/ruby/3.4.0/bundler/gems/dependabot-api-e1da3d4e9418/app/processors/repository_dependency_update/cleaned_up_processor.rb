# frozen_string_literal: true

module RepositoryDependencyUpdate
  class CleanedUpProcessor < ApplicationProcessor
    group_name "repository_dependency_update_cleaned_up"
    handle_topic(/github\.v1\.RepositoryDependencyUpdateCleanedUp\Z/, CleanedUpHandler)
  end
end
