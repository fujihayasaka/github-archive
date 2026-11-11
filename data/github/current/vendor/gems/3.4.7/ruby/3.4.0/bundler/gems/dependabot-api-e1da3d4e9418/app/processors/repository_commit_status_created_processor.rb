# frozen_string_literal: true

class RepositoryCommitStatusCreatedProcessor < ApplicationProcessor
  group_name "repository_commit_status_created"
  handle_topic(/github\.v1\.RepositoryCommitStatusCreated\Z/, RepositoryCommitStatusCreatedHandler)

  def initialize
    options[:session_timeout] = 5.minutes
  end
end
