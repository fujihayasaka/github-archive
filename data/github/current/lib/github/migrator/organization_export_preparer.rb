# typed: true
# frozen_string_literal: true

# OrganizationExportPreparer is a service object that will prepare an organization export
# and its dependencies to be exported.
#
# To prepare the Organization, a MigratableResource  with the organization's
# guid will be created for the Organization and each of its dependent
# models.
#
# The dependencies of a Repository are defined as:
# - The Repository's owner (Organization)
# - All of that Organization's Teams
# - All of that Organization's Settings
# - All of that Organization's Members
# - All of that Organization's Projects
#
module GitHub
  class Migrator
    class OrganizationExportPreparer
      BATCH_SIZE = 1000

      # Public: Instantiates an OrganizationExportPreparer for the given organization and migration
      # represented by guid.
      #
      # organization (Required) - Organization that will be exported to an archive.
      # guid (Required)       - A unique identifier representing the migration this model
      #                         will be prepared for.
      # options values:
      # events:               - An instance of GitHub::Migrator::Events that will notify its
      #                         subscribers of progress.
      # exclude_owner_projects - If true, will not include owner-level projects. Defaults to false.
      # org_metadata_only         - If true, will override all other variables and only export org metadata. Defaults to false.
      #
      def initialize(organization:, guid:, options: nil)
        options ||= {}
        @organization           = organization
        @guid                   = guid
        @exclude_owner_projects = options.fetch(:exclude_owner_projects, false)
        @org_metadata_only      = options.fetch(:org_metadata_only, false)
        @events                 = options.fetch(:events) { GitHub::Migrator::Events::Null.new }
        @cache                  = GitHub::Migrator::Cache.new
      end

      # Public: Execute the action. Creates all of the MigratableResources for the
      # given Organization and its dependencies.
      #
      # Raises an exception if any required options are not present.
      #
      # Returns a Hash with a count of each model type that is prepared for exporting.
      def call
        validate

        # Create MigratableResources for the Organization and its dependents
        export_builder.add(organization)

        add_owner_teams_and_members(organization)
        add_owner_projects(organization)
        add_repositories(organization)

        # Finalize
        export_builder.complete

        # Generate report hash and return
        migratable_resources = MigratableResource.for_guid(guid)
        GitHub::Migrator::MigrationReporter.migrator_result(migratable_resources)
      ensure
        cache.clear
      end

      private

      attr_reader :organization, :cache, :events, :guid, :exclude_owner_projects, :org_metadata_only

      # validate that required options are present
      def validate
        if organization.nil?
          raise GitHub::Migrator::OrganizationRequired
        end
        if guid.nil?
          raise GitHub::Migrator::GuidRequired
        end
        unless organization.try(:organization?)
          raise GitHub::Migrator::OrganizationRequired
        end
      end

      def export_builder
        @export_builder ||= GitHub::Migrator::MigratableResourceExportBuilder.new \
          guid: guid,
          model_url_service: GitHub::Migrator::ModelUrlService.new(cache: cache),
          progress: lambda { |*x| events.fire(*x) }
      end

      def add_owner_teams_and_members(owner)
        export_builder.add(owner)

        owner.members.find_each do |user|
          export_builder.add(user)
        end

        owner.teams.find_each do |team|
          export_builder.add(team)
        end
      end

      def add_owner_projects(owner)
        return if exclude_owner_projects
        owner.projects.find_each do |project|
          export_builder.add(project)
          export_builder.add(project.creator)
        end
      end

      def add_project_card_creators(project_ids)
        project_ids.each_slice(BATCH_SIZE) do |project_batch_ids|
          ProjectCard.where(project_id: project_batch_ids).find_each do |project_card|
            export_builder.add(user_id: project_card.creator_id)
          end
        end
      end

      def add_repositories(owner)
        owner.repositories.find_each do |repo|
          export_builder.add(repo)
        end
      end
    end
  end
end
