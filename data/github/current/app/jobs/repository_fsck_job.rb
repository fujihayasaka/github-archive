# typed: false
# frozen_string_literal: true

class RepositoryFsckJob < ApplicationJob
  queue_as :repository_fsck
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  def perform(repo_id)
    repository = Repository.find_by_id(repo_id)
    repository&.fsck!
  end
end
