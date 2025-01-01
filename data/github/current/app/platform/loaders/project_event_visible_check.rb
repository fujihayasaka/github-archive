# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ProjectEventVisibleCheck < Platform::Loader
      include Scientist

      def self.load(viewer, repository_id, issue_event_id)
        self.for(viewer, repository_id).load(issue_event_id)
      end

      def initialize(viewer, repository_id)
        @viewer = viewer
        @repository_id = repository_id
      end

      def fetch(issue_event_ids)
        project_id_by_issue_event_id = ::IssueEventDetail.where({
          issue_event_id: issue_event_ids,
          subject_type: "Project"
        }).pluck(:issue_event_id, :subject_id).to_h

        project_ids = project_id_by_issue_event_id.values.uniq
        return Hash.new(false) if project_ids.empty?

        ability_project_ids = []

        if @viewer
          ability_project_ids.concat(direct_project_ids(project_ids))
          ability_project_ids.concat(adminable_project_ids(project_ids))
          ability_project_ids.concat(indirect_via_children_project_ids(project_ids))
        end

        project_ids_scope = Project.where(id: project_ids, deleted_at: nil)

        if @viewer && ability_project_ids.any?
          project_ids_scope = project_ids_scope.where("owner_type = 'Repository' OR (owner_type IN  ('Organization', 'User') AND (id IN (?) OR owner_id = ? OR public = 1))", ability_project_ids, @viewer.id)
          project_ids_scope = project_ids_scope_with_auth_via_granular_actor(project_ids_scope) if @viewer.using_auth_via_granular_actor?
        elsif @viewer && @viewer.can_have_granular_permissions?
          async_projects = project_ids_scope.includes(:owner).map do |project|
            project.owner.async_projects_readable_by?(@viewer).then do |readable|
              project if readable
            end
          end

          async_project_ids_scope = Promise.all(async_projects).then do |projects|
            ArrayWrapper.new(projects.compact)
          end

          project_ids_scope = async_project_ids_scope.sync
        elsif @viewer
          project_ids_scope = project_ids_scope.where("owner_type = 'Repository' OR (owner_type IN  ('Organization', 'User') AND (owner_id = ? OR public = 1))", @viewer.id)
          project_ids_scope = project_ids_scope_with_auth_via_granular_actor(project_ids_scope) if @viewer.using_auth_via_granular_actor?
        else
          project_ids_scope = project_ids_scope.where("owner_type = 'Repository' OR (owner_type IN  ('Organization', 'User') AND public = 1)")
        end

        project_ids_with_owner = project_ids_scope.pluck(:id, :owner_type, :owner_id)

        return Hash.new(false) if project_ids_with_owner.empty?

        visible_project_ids = Set.new

        Promise.all(project_ids_with_owner.map do |(project_id, owner_type, owner_id)|
          async_project_enabled = case owner_type
          when "User"
            # User owned projects are always enabled
            Promise.resolve(true)
          when "Repository"
            RepositoryProjectsEnabledCheck.load(owner_id)
          when "Organization"
            OrganizationProjectsEnabledCheck.load(owner_id)
          end

          async_project_enabled.then do |enabled|
            next unless enabled
            if owner_type == "Repository" && owner_id != @repository_id
              GitHub.dogstats.increment("project_event_visible.repository_mismatch")
              Failbot.report(ProjectRepositoryMismatch.new(project_id, owner_id, @repository_id))
              RepositoryVisibleCheck.load(@viewer, owner_id, resource: "contents").then do |visible|
                visible_project_ids << project_id if visible
              end
            else
              visible_project_ids << project_id
            end
          end
        end).sync

        issue_event_ids.map do |issue_event_id|
          if (project_id = project_id_by_issue_event_id[issue_event_id])
            [issue_event_id, visible_project_ids.include?(project_id)]
          else
            [issue_event_id, true]
          end
        end.to_h
      end

      private

      def adminable_project_ids(project_ids)
        org_owned_project_org_ids = Project.where(owner_type: "Organization", id: project_ids).pluck(:owner_id)
        project_orgs_viewer_admins = ::Ability.
                                            where(actor_id: @viewer.id,
                                                  actor_type: "User",
                                                  subject_type: "Organization",
                                                  subject_id: org_owned_project_org_ids,
                                                  action: ::Ability.actions[:admin])
                                            .pluck(:subject_id)
        projects_user_can_admin = Project.where(id: project_ids, owner_id: project_orgs_viewer_admins).pluck(:id)
      end

      def direct_project_ids(project_ids)
        ::Ability.direct.
          where(actor_id: @viewer.id,
                actor_type: "User",
                subject_id: project_ids,
                subject_type: "Project").
                distinct.pluck(:subject_id)
      end

      def indirect_via_children_project_ids(project_ids)
        ::Ability.indirect_via_children.
          where(actor_id: @viewer.id,
                actor_type: "User",
                children: { subject_id: project_ids,
                            subject_type: "Project" })
                .distinct.pluck("children.subject_id")
      end

      def project_ids_scope_with_auth_via_granular_actor(project_ids_scope)
        cached_targets_and_grants = {}

        async_projects = project_ids_scope.includes(:owner).map do |project|
          owner = project.owner

          grantable = case project.owner_type
          when "Repository"
            cached_targets_and_grants.fetch(owner, ProgrammaticActor::Grant.with(@viewer).with_repository(owner))
          else
            cached_targets_and_grants.fetch(owner, ProgrammaticActor::Grant.with(@viewer).with_target(owner))
          end

          cached_targets_and_grants[owner] = grantable

          if grantable
            project.owner.async_projects_readable_by?(grantable).then do |readable|
              project if readable
            end
          end
        end

        async_project_ids_scope = Promise.all(async_projects).then do |projects|
          ArrayWrapper.new(projects.compact)
        end

        async_project_ids_scope.sync
      end

      class ProjectRepositoryMismatch < Errors::Internal
        def initialize(project_id, project_owner_id, repository_id)
          message = <<~MSG
          A project defined in a repository is having an issue event attached to an issue in another repository
          Project id: #{project_id}
          Project owner id: #{project_owner_id}
          Repository id: #{repository_id}
          MSG
          super(message)
        end
      end
    end
  end
end
