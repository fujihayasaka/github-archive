# typed: false
# frozen_string_literal: true

class DeleteProjectJob < ApplicationJob
  queue_as :archive_project

  retry_on_dirty_exit

  locked_by timeout: 1.hour, key: ->(job) {
    job.arguments[0]
  }

  def perform(project_id, actor_id)
    logger.info("GitHub::Jobs::DeleteProject (%{project_id})" % { project_id: project_id })

    return unless actor_id && project = Project.find_by_id(project_id)

    Failbot.push("gh.projects.project.id": project_id)

    GitHub.context.push(actor_id: actor_id) do
      with_write do
        Archived::Project.archive(project)
      end
    end
  end
end
