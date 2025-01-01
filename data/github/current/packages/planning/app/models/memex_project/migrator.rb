# typed: true
# frozen_string_literal: true

class MemexProject::Migrator
  include GitHub::Memoizer

  class MissingActorError < StandardError; end
  class MissingProjectError < StandardError; end
  class MigrationError < StandardError; end

  DEFAULT_SCHEMA_PATH = File.join(Rails.root, "packages/planning/app/models/memex_project/migrator/schemas/v1/project.json")

  attr_reader :actor, :migration, :spec

  # If true, we will skip various validations in memex models which are cumbersome when migrating projects in bulk.
  @@migrating = T.let(false, T::Boolean)

  # Enables "bulk mode" within the given block of code, which disables a variety of validations for Memex models
  sig { params(blk: T.proc.void).returns(T.untyped) }
  def self.with_migrating(&blk)
    begin
      @@migrating = true
      yield
    ensure
      @@migrating = false
    end
  end

  # Returns whether or not we are currently migrating a project
  sig { returns(T::Boolean) }
  def self.migrating?
    @@migrating
  end

  def self.initialize!(requester, project)
    project_migration = ProjectMigration.new(requester: requester, project: project)
    migration_with_spec = new(requester, project_migration, nil).add_spec!
    migration_with_spec
  end

  def self.add_spec!(project_migration_id)
    project_migration = ProjectMigration.find(project_migration_id)
    requester = project_migration.requester
    raise MissingActorError.new("Actor not found") unless requester

    legacy_project = project_migration.project
    raise MissingProjectError.new("Project not found") unless legacy_project

    migration_with_spec = new(requester, project_migration, nil).add_spec!
    migration_with_spec
  end

  def self.migrate!(project_migration_id)
    project_migration = ProjectMigration.find(project_migration_id)
    actor = project_migration.requester
    raise MissingActorError.new("Actor not found") unless actor

    legacy_project = project_migration.project
    raise MissingProjectError.new("Project not found") unless legacy_project

    Failbot.push("gh.memex.migration.source_project.id": legacy_project.id)
    Failbot.push("gh.memex.migration.requester.id": project_migration.requester_id)

    spec = Specification.new(legacy_project.to_memex_specification)
    spec.validate!

    new(actor, project_migration, spec).migrate!
  end

  def initialize(actor, project_migration, spec)
    @actor = actor
    @migration = project_migration
    @spec = spec
  end

  def migrate!
    # For the duration of this migrate method, enabling "migrating" mode, which will disable certain validations
    # which are cumbersome to do while migrating project in bulk
    self.class.with_migrating do
      # For the duration of the migration, skip updating the `updated_at` fields on models. It should be populated
      # as part of creating a new record anyway, so we don't need to update it when we edit items in the project
      ActiveRecord::Base.no_touching do
        # only create a new project if one doesn't already exist (previous migration may have failed)
        if migration.memex_project
          memex = migration.memex_project
        else
          memex = migrate_basic_project_structure!(spec)
          migration.update!(memex_project: memex)
        end

        if repository.present?
          # link the org owned memex for curation if the repo owns the classic project
          link_project(repository, memex)
        end

        unless migration.has_completed?(:in_progress_status_fields)
          migration.in_progress_status_fields!
          memex.configure_status_field!(spec[:status_field])
          send_live_update(memex, migration)
        end

        unless migration.has_completed?(:in_progress_default_view)
          migration.in_progress_default_view!
          memex.configure_default_view!(spec[:views]&.first)
          send_live_update(memex, migration)
        end

        unless migration.has_completed?(:in_progress_permissions)
          migration.in_progress_permissions!
          memex.configure_permissions!(spec[:permissions])
          send_live_update(memex, migration)
        end

        unless migration.has_completed?(:in_progress_items)
          migration.in_progress_items!
          memex.populate_items!(actor, spec[:items], migration)
          send_live_update(memex, migration)
        end

        unless migration.has_completed?(:in_progress_workflows)
          migration.in_progress_workflows!
          field_id_store = FieldIdStore.new(memex, spec)
          field_option_id_store = FieldOptionIdStore.new(memex, spec)
          memex.migrate_workflows!(spec[:workflows], actor, field_id_store, field_option_id_store)
          send_live_update(memex, migration)
        end

        unless migration.completed?
          migration.completed!
          send_live_update(memex, migration)
        end

        migration.project.notify_metadata_subscribers

        memex
      end
    end
  end

  def migrate_basic_project_structure!(spec)
    creation_options = spec.slice(:title, :description, :short_description, :public)
    memex = MemexProject.create_with_associations(**T.unsafe({ owner: owner, creator: actor, with_default_workflows: spec[:workflows].blank?, **creation_options }))
    raise MigrationError.new(memex.errors.full_messages.to_sentence) unless memex.persisted?
    memex
  end

  def add_spec!
    spec = Specification.new(@migration.project.to_memex_specification)
    spec.validate!
    @spec = spec

    memex = migrate_basic_project_structure!(spec)
    @migration.update!(memex_project: memex)

    @migration.in_progress_status_fields!
    memex.configure_status_field!(spec[:status_field])

    @migration.in_progress_default_view!
    memex.configure_default_view!(spec[:views]&.first)

    @migration
  end

  private def send_live_update(memex, migration)
    memex.notify_memex_channel(live_update_payload(migration))
  end

  private def live_update_payload(migration)
    payload = migration.as_json(dangerously_allow_all_keys: true, include: {
      project: {
        only: [:name],
        methods: :closed?
      }
    }, methods: :is_automated)

    payload["project_migration"]["project"]["closed"] = payload.dig("project_migration", "project").delete("closed?")
    payload["project_migration"]["source_project"] = payload["project_migration"].delete "project"
    payload["project_migration"]["source_project"]["path"] = migration.project.path
    payload["project_migration"]["source_project"]["empty"] = migration.project.empty?
    payload.as_json
  end

  # Creates a project link between a source repository and the memex project
  #
  # Returns Boolean to determine whether the link was created or not
  private def link_project(source, memex)
    return false unless source && memex
    memex.memex_project_links.find_or_create_by(source: source)
  end

  sig { returns(T.nilable(T.any(Organization, User))) }
  memoize private def owner
    if spec[:owner_type] == Organization.name
      Organization.find_by(id: spec[:owner_id])
    elsif spec[:owner_type] == Repository.name
      repository&.owner
    else
      User.find_by(id: spec[:owner_id])
    end
  end

  sig { returns(T.nilable(Repository)) }
  memoize private def repository
    return unless spec[:owner_type] == Repository.name
    if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      T.cast(Repositories.domain.by_id(spec[:owner_id]), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: spec[:owner_id])
    end
  end
end
