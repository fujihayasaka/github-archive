# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MigrateGhesClassicProjects < Base
      iterate_over :database_table, params: {
        model_class: Project,
        conditions: "closed_at IS NULL",
        columns: %i[id],
      }

      sig { override.void }
      def after_initialize
        return unless GitHub.enterprise?
        # We will use the memex automation bot as the "creator" for all of the items in a project. That is because we
        # need a "user" that has full access to all of the items in the project to create new items.
        @creator = T.let(Apps::Privileged::MemexAutomation.bot, T.nilable(Bot))
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        return unless GitHub.enterprise?

        projects_errored = []

        project_ids = items.keys
        projects = Project.where(id: project_ids)
        GitHub::PrefillAssociations.prefill_associations(
          projects,
          [:columns, :project_workflows, :owner]
        )

        log("Migrating batch of projects", {
          project_count: projects.length
        })
        projects.each do |project|
          project = T.let(project, Project)
          log("Migrating project", { project_id: project.id })
          begin
            GitHub.tracer.in_span("transition project migration", kind: :internal, attributes: {
              "gh.project.id" => project.id
            }) do
              migrate_project(project)
            end
          rescue => e # rubocop:todo Lint/GenericRescue
            projects_errored << project.id
            project_migration = project.project_migration
            project_status = if project_migration.nil?
              "no migration created for project"
            else
              status = project_migration.status
              Failbot.push("gh.projects.project_migration.status": status)
              status
            end
            log("Failed to migrate project", {
              project_id: project.id,
              status: project_status
            })
            Failbot.push("gh.projects.project.id": project.id)
            Failbot.report(e)
          end
        end
        log("Some projects failed in current batch", {
          project_ids: projects_errored.join(",")
        }) if projects_errored.length > 0
      end

      sig { params(project: ::Project).void }
      def migrate_project(project)
        if project.closed?
          log("Project already closed", {
            project_id: project.id,
          })
          return
        end
        start_time = Time.now
        # We can't create a ProjectMigration without a requester and a memex project, so we only save the migration
        # after we set up everthing we can for it.
        # We also specifically want to find a migration created by our automation bot to resume, and not find migrations
        # executed by users in the past.
        migration = ProjectMigration.find_or_initialize_by(project:, requester: @creator)

        if migration.completed?
          log("Project already migrated", {
            project_id: project.id,
          })
          return
        end

        repository = if project.owner_type == "Repository"
          project.owner
        else
          nil
        end
        owner = if project.owner_type == "Repository"
          repository.owner
        else
          project.owner
        end

        # Generating a spec from a legacy project itself makes requests for a large number of rows, so we've chosen to
        # leave this as is, instead of abstracting that prefilling to be more easily done for a large number of projects.
        # This also allows us to keep that logic which has already been thoroughly tested in the migrator instead of
        # attempting to duplicate it here.
        spec = MemexProject::Migrator::Specification.new(project.to_memex_specification)
        spec.validate!

        if dry_run?
          log("[dry run] would create project #{project.id} with #{spec.dig(:items)&.length} items, #{spec.dig(:workflows)&.length} workflows, and #{spec.dig(:permissions)&.length} permissions")
          return
        end

        # much of the code below is copied from https://github.com/github/github/blob/b77db7e191aa024fc58974bed557d6eaa7c57f23/packages/planning/app/models/memex_project/migrator.rb#L76
        # I opted to copy it here for reviewability, and there is a tight development loop working on this temporary
        # migration, so it seemed best to copy it here.
        MemexProject::Migrator.with_migrating do
          ActiveRecord::Base.no_touching do
            # only create a new project if one doesn't already exist (previous migration may have failed)
            memex = if migration.memex_project
              T.must(migration.memex_project)
            else
              creation_options = spec.slice(:title, :description, :short_description, :public)
              # These write_to blocks don't necessarily return the response, so we have to do a little workaround
              # and save off the new memex to a variable that we set inside the passed block
              new_memex = T.let(nil, T.nilable(MemexProject))
              write_to(model_class: MemexProject) do
                write_to(model_class: ApplicationRecord::Domain::Sequences) do
                  new_memex = MemexProject.create_with_associations(**T.unsafe({ owner: owner, creator: @creator, with_default_workflows: spec[:workflows].blank?, with_mwl_enabled: false, **creation_options }))
                end
              end
              migration.memex_project = new_memex
              T.must(new_memex)
            end

            unless migration.memex_project&.persisted?
              log("Failed to create memex project for migration", {
                owner_id: owner.id,
                project_id: project.id,
                project_number: project.number,
              })
              return
            end

            write_to(model_class: ProjectMigration) do
              migration.save!
            end

            # Link a memex to a repository if this project is already owned by a repository
            if repository.present?
              write_to(model_class: MemexProject) do
                memex.memex_project_links.find_or_create_by(source: repository)
              end
            end

            # We flip this flag when we perform a step, and that allows us to log where a migration resumed it begins
            # at any step beyond the first
            step_performed = false

            # To make migrations idempotent, we check their current status to ensure that we are able to restart them
            # at the correct spot if they quit or error mid-migration
            # Each of the statements below represent a portion of that progress
            unless migration.has_completed?(:in_progress_status_fields)
              step_performed = true
              write_to(model_class: MemexProject) do
                migration.in_progress_status_fields!
              end
              memex.configure_status_field!(spec[:status_field])
            end

            unless migration.has_completed?(:in_progress_default_view)
              log("Project id #{project.id} resumed at default_view step") unless step_performed
              step_performed = true
              write_to(model_class: MemexProject) do
                migration.in_progress_default_view!
              end
              memex.configure_default_view!(spec[:views]&.first)
            end

            unless migration.has_completed?(:in_progress_permissions)
              log("Project id #{project.id} resumed at permission step") unless step_performed
              step_performed = true
              write_to(model_class: MemexProject) do
                migration.in_progress_permissions!
              end
              memex.configure_permissions!(spec[:permissions])
            end

            unless migration.has_completed?(:in_progress_items)
              log("Project id #{project.id} resumed at items step") unless step_performed
              step_performed = true
              write_to(model_class: MemexProject) do
                migration.in_progress_items!
              end
              memex.populate_items!(@creator, spec[:items], migration)
            end

            unless migration.has_completed?(:in_progress_workflows)
              log("Project id #{project.id} resumed at workflow step") unless step_performed
              step_performed = true
              write_to(model_class: MemexProject) do
                migration.in_progress_workflows!
              end
              field_id_store = MemexProject::Migrator::FieldIdStore.new(memex, spec)
              field_option_id_store = MemexProject::Migrator::FieldOptionIdStore.new(memex, spec)
              memex.migrate_workflows!(spec[:workflows], @creator, field_id_store, field_option_id_store)
            end


            if !migration.completed?
              # Finally, we can close the old project
              write_to(model_class: Project) do
                project.close
              end

              write_to(model_class: MemexProject) do
                migration.completed!
              end

              log("Project fully migrated", {
                owner_id: owner.id,
                project_id: project.id,
                memex_project_id: memex.id,
                project_number: project.number,
                memex_number: memex.number,
                item_count: spec.dig(:items)&.length,
                workflow_count: spec.dig(:workflows)&.length,
                permission_count: spec.dig(:permissions)&.length,
                duration_seconds: Time.now - start_time,
              })
            end
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::MigrateGhesClassicProjects.new(args).run
end
