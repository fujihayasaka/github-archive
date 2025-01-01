# typed: strict
# frozen_string_literal: true

# LinkMemexProjectToRepositoryJob creates a MemexProjectLink between a MemexProject and its
# default_issue_create_target_repository when it's set during onboarding, or updated after the fact.
class LinkMemexProjectToRepositoryJob < ApplicationJob
  queue_as :memex_project_links

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  discard_on ActiveRecord::RecordNotFound
  discard_on ActiveRecord::RecordInvalid do |job, error|
    memex_project_id, repository_id = job.arguments
    Failbot.report(error)
    GitHub.logger.error(error,
      "code.namespace" => "LinkMemexProjectToRepositoryJob",
      "code.function" => "perform",
      "gh.repo.id" => repository_id,
      "gh.memex.project.id" => memex_project_id,
    )
  end

  sig { params(memex_project_id: Integer, repository_id: Integer).void }
  def perform(memex_project_id, repository_id)
    return unless memex_project = MemexProject.find_by(id: memex_project_id)
    return unless repository = Repository.find_by(id: repository_id)

    # Only create the link if one doesn't already exist
    return if memex_project.memex_project_links.exists?(source: repository)

    # Create the link
    with_write do
      memex_project.memex_project_links.create!(
        source: repository
      )
    end
  end
end
