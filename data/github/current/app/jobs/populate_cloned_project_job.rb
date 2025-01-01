# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

# Used by the CloneProject mutation to populate a cloned project from a source project
#
# Requires:
#   - status_id: JobStatus id for tracking
#   - target_project_id: the new *empty* project to copy everything to
#   - source_project_id: the project to copy the column contents from
#   - actor_id: the actor requesting the clone
#   - include_workflows: boolean, whether or not to copy workflows

class PopulateClonedProjectJob < ApplicationJob
  # Use primary connection for writing data to projects, project_columns, project_workflows tables.
  use_primaries ApplicationRecord::Mysql1,
  # Use primary connection for writing data to key_values table.
  ApplicationRecord::Memex

  queue_as :populate_cloned_project
  retry_on_dirty_exit

  def self.prefix
    name
  end

  def self.job_id
    "#{prefix}_#{SecureRandom.uuid}"
  end

  def perform(target_project_id, source_project_id, arguments = {})
    start = Time.current
    arguments = arguments.with_indifferent_access
    status_id, queued_at = arguments.values_at("status_id", "queued_at")

    # `queued_at` may be a String or an instance of Time depending on argument
    # serialization. To be safe, convert to a string before parsing
    GitHub.dogstats.timing_since("job.populate_cloned_project.time_enqueued", Time.parse(queued_at.to_s))
    status = Memex::JobStatus.find(status_id)

    return unless status
    return unless project = Project.find_by_id(target_project_id)

    status.track do
      actor_id, include_workflows = arguments.values_at("actor_id", "include_workflows")

      return unless source_project = Project.find_by_id(source_project_id)
      return unless actor = User.find_by_id(actor_id)

      return unless source_project.readable_by?(actor) && project.writable_by?(actor)
      return unless project.columns.empty?

      GitHub.context.push(clone_project_from_job: project.id)
      Audit.context.push(clone_project_from_job: project.id)

      source_columns = source_project.columns
      source_columns.includes(:project_workflows) if include_workflows

      source_columns.each do |source_column|
        ProjectColumn.throttle do
          column = project.columns.create(
            name: source_column.name,
            position: source_column.position,
            purpose: source_column.purpose,
          )

          if include_workflows
            source_column.project_workflows.each do |workflow|
              project.project_workflows.set_workflow(trigger_type: workflow.trigger_type, creator: actor, column: column)
            end
          end
        end
      end
    end
    ensure
      GitHub.dogstats.timing_since("job.populate_cloned_project.time", start)
      project&.unlock(Project::ProjectLock::PROJECT_CLONING)
  end
end
