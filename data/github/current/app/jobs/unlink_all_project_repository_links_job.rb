# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# UnlinkAllProjectRepositoryLinks is used by Stafftools to sever repository
# links when transferring a top-level owned project to a repository owner
#
# Call `Project#unlink_repositories` to enqueue the job

class UnlinkAllProjectRepositoryLinksJob < ApplicationJob
  queue_as :unlink_project_repo_links

  retry_on_dirty_exit

  def perform(project_id, actor_id)
    return unless project = Project.find_by(id: project_id)
    return unless actor = User.find_by(id: actor_id)

    repositories = project.linked_repositories
    return unless repositories.any?

    # Necessary for instrumentation to avoid Ghost user
    GitHub.context.push(actor_id: actor.id)
    repositories.each do |repository|
      with_write do
        project.unlink_repository(repository)
      end
    end
  end
end
