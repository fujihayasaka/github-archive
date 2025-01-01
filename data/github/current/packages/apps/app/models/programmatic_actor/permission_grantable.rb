# typed: true
# frozen_string_literal: true

module ProgrammaticActor
  module PermissionGrantable
    include Scientist

    BATCH_SIZE = 1000

    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { Kernel }

    included do
      extend ClassMethods
    end

    ProgrammaticActorTypes = T.type_alias do
      T.any(
        GlobalIntegrationInstallation,
        IntegrationInstallation,
        OrganizationProgrammaticAccessGrant,
        OrganizationProgrammaticAccessGrantRequest,
        ScopedIntegrationInstallation,
        SiteScopedIntegrationInstallation,
        UserProgrammaticAccessGrant,
        UserProgrammaticAccessGrantRequest,
      )
    end

    # Internal: Can this programmatic actor have granular permissions on resources?
    #
    # Returns true.
    def can_have_granular_permissions?
      true
    end

    # Internal: Can this programmatic actor have granular permissions on user resources?
    #
    # Returns false.
    def can_have_granular_user_permissions?
      false
    end

    def actor_type
      self.class.actor_type
    end

    def permissions
      case self
      when IntegrationInstallation
        feature_enabled?(:cached_fgp_permissions) ? get_cached_permissions : permission_results
      else
        permission_results
      end
    end

    def permission_results
      T.bind(self, ProgrammaticActorTypes)

      permissions = Permission.connection.select_rows(Arel.sql(<<~SQL, actor_id: ability_id, actor_type: actor_type))
        SELECT DISTINCT subject_type, action
        FROM permissions
        WHERE actor_type = :actor_type
        AND actor_id = :actor_id
      SQL

      permissions.each_with_object({}) do |permission, memo|
        subject_type, action = permission

        resource = subject_type.split("/").last
        memo[resource] = T.must(Permission.actions.key(action)).to_sym
      end
    end

    # Public: Does this grantable (Installation or Grant) have repository access
    # granted by Permission records?
    #
    # Returns a Boolean.
    def installed_on_repositories?
      (permissions.keys & Repository::Resources.subject_types).any?
    end

    # Public: Has this grantable been installed on all repositories?
    #
    # min_action: - An optional Symbol representing the minimum ability action
    #               (:read, :write, or :admin) that the user must have for the
    #               repositories. Default is nil, for no min_action
    #               restrictions.
    # resource:   - An optional String to represent a collection, from
    #               Repository::Resources.subject_types, to limit results to an installation with
    #               permissions on that resource.
    #
    # Examples:
    #
    #   installed_on_all_repositories?(resource: "issues")
    #   installed_on_all_repositories?(resource: "pull_requests")
    #   installed_on_all_repositories?(min_action: :write, resource: "contents")
    #
    # Returns Boolean.
    def installed_on_all_repositories?(min_action: :read, resource: nil)
      is_candidate_enabled = GitHub.flipper[:permission_grantable_installed_on_all_repositories_candidate].enabled?
      version = is_candidate_enabled ? "candidate" : "control"
      tags = ["min_action:#{min_action}", "actor_type:#{actor_type.underscore}", "version:#{version}"]
      GitHub.dogstats.distribution_time("permission_grantable.installed_on_all_repositories", tags: tags) do
        subject_types = if resource.present?
          ["#{Repository::Resources::ALL_ABILITY_TYPE_PREFIX}/#{resource.downcase}"]
        else
          Repository::Resources.all_type_prefixed_subject_types
        end

        if is_candidate_enabled
          installed_on_all_repositories_candidate(min_action: min_action, subject_types: subject_types)
        else
          installed_on_all_repositories_control(min_action: min_action, subject_types: subject_types)
        end
      end
    end

    def installed_on_all_repositories_candidate(min_action:, subject_types:)
      T.bind(self, ProgrammaticActorTypes)

      Permissions::Service.installed_on_all_repositories?(
        actor_id: ability_id,
        actor_type: ability_type,
        min_action: min_action,
        subject_types: subject_types
      )
    end

    def installed_on_all_repositories_control(min_action:, subject_types:)
      T.bind(self, ProgrammaticActorTypes)

      args = {
        actor_id:      ability_id,
        actor_type:    ability_type,
        min_action:    Ability.actions[min_action],
        subject_types: Array(subject_types),
      }

      sql = Arel.sql(<<-SQL, **args)
        SELECT 1 as one
        FROM permissions
        WHERE actor_id = :actor_id
          AND actor_type = :actor_type
          AND action >= :min_action
          AND subject_type IN (:subject_types)
        LIMIT 1
      SQL

      Permission.connection.select_values(sql).any?
    end

    def installed_on_selected_repositories?
      !installed_on_all_repositories?
    end

    # Internal: which repositories does this grantable have any permission on
    #
    # min_action: - An optional Symbol representing the minimum ability action
    #               (:read, :write, or :admin) that the user must have for the
    #               returned repositories. Default is nil, for no min_action
    #               restrictions.
    # resource:   - An optional String to represent a collection, from
    #               Repository::Resources.subject_types, to limit results to repositories with
    #               permissions on that resource.
    # repository_ids: - An optional list of candidate repository ids. Only
    #                   repositories that are in this list and are accessible by
    #                   the integration will be returned.
    # Examples:
    #
    #   repository_ids(resource: "issues")
    #   repository_ids(resource: "pull_requests")
    #   repository_ids(min_action: :write, resource: "contents")
    #
    # Returns an Array
    def repository_ids(min_action: nil, resource: nil, repository_ids: nil, organization: nil)
      T.bind(self, ProgrammaticActorTypes)

      return [] if resource && Repository::Resources.subject_types.none?(resource.to_s)
      return [] if self.new_record?

      min_action ||= :read

      if installed_on_all_repositories?(min_action: min_action, resource: resource)
        async_target.then do |target|
          next [] if organization && target != organization
          next [] unless target

          ids = Repositories.domain.repo_ids_by_owner(
            owner_id: target.id,
            public_only: false,
            repo_ids_in: repository_ids
          )

          next [] if ids.none?

          workspace_repo_ids = RepositoryAdvisory.where(owner_id: target.id).pluck(:workspace_repository_id)

          ids - workspace_repo_ids
        end.sync
      else
        installed_on_individual_repository_ids(min_action: min_action, resource: resource, repository_ids: repository_ids, organization: organization)
      end
    end

    # Public: the number of unique repositories this grantable has any permission on
    #
    # Returns an Integer.
    def repositories_count
      T.bind(self, ProgrammaticActorTypes)
      return 0 if self.new_record?

      GitHub.dogstats.distribution_time("permission_grantable.repositories_count") do
        if installed_on_all_repositories?(min_action: :read, resource: :metadata)
          return science "permission_grantable.repositories_count" do |e|
            e.use { repository_ids(min_action: :read, resource: :metadata).count }
            e.try do
              async_target.then do |target|
                next 0 unless target

                repo_count = Repositories.domain.repo_ids_by_owner_count(
                  owner_id: target.id,
                  public_only: false,
                  repo_ids_in: nil
                )

                next 0 if repo_count.zero?

                workspace_repo_count = RepositoryAdvisory.where(owner_id: target.id).count

                repo_count - workspace_repo_count
              end.sync
            end
          end
        end

        Permission
          .select(:subject_id)
          .where(
            actor_id: ability_id,
            actor_type: ability_type,
            subject_type: Repository.new.resources.metadata.ability_type,
          )
          .count
      end
    end

    # Public: which repositories does this grantable have any permission on
    #
    # See #repository_ids for detailed docs.
    #
    # Returns a scoped relation for the associated repositories.
    def repositories(min_action: :read, resource: nil)
      T.bind(self, ProgrammaticActorTypes)

      if GitHub.flipper[:skip_repository_ids_call_for_installs_on_all].enabled?
        return Repositories::Public.none if resource && Repository::Resources.subject_types.none?(resource.to_s)
        return Repositories::Public.none if self.new_record?

        if installed_on_all_repositories?(min_action: min_action, resource: resource)
          async_target.then do |target|
            scope = target.repositories
            workspace_repos = RepositoryAdvisory.where(owner_id: target.id)

            if workspace_repos.exists?
              scope = scope.where.not(id: workspace_repos.pluck(:workspace_repository_id))
            end

            scope
          end.sync
        else
          repo_ids = installed_on_individual_repository_ids(min_action: min_action, resource: resource)

          if repo_ids.none?
            Repositories::Public.none
          else
            Repositories::Public.load_repositories(repo_ids)
          end
        end
      else
        repo_ids = repository_ids(min_action: min_action, resource: resource)

        if repo_ids.none?
          Repositories::Public.none
        else
          Repository.where(id: repo_ids).active
        end
      end
    end

    def organization_ids(resource:)
      T.bind(self, ProgrammaticActorTypes)

      subject_type = Organization::Resources.all_prefixed_subject_types([resource]).first
      return [] if subject_type.nil?

      Permissions::Service.subject_ids_granted_permission(
        actor_ids: [self.ability_id],
        actor_type: self.ability_type,
        subject_type:,
        action: Permission.actions.values # read, write, admin
      )
    end

    module ClassMethods
      extend T::Helpers

      requires_ancestor { Kernel }

      ProgrammaticActorClasses = T.type_alias do
        T.any(
          T.class_of(IntegrationInstallation),
          T.class_of(OrganizationProgrammaticAccessGrant),
          T.class_of(OrganizationProgrammaticAccessGrantRequest),
          T.class_of(ScopedIntegrationInstallation),
          T.class_of(SiteScopedIntegrationInstallation),
          T.class_of(UserProgrammaticAccessGrant),
          T.class_of(UserProgrammaticAccessGrantRequest),
        )
      end

      def actor_type
        T.bind(self, ProgrammaticActorClasses)

        name
      end

      # With permissions on the given Repository.
      def with_repository(repository)
        raise ArgumentError, "Repository required" if repository.nil?
        with_resources_on(subject: repository, resources: Repository::Resources.subject_types)
      end

      def with_resources_on(subject:, resources:, min_action: :read)
        T.bind(self, ProgrammaticActorClasses)

        where(id: T.unsafe(self).ids_with_resources_on(
          subject_class:    subject.class,
          subject_id:       subject.id,
          subject_owner_id: subject.is_a?(User) ? nil : subject.owner_id,
          resources:        resources,
          min_action:       min_action
        ))
      end

      def ids_with_resources_on(subject_class:, subject_id:, subject_owner_id:, resources:, min_action: :read)
        Authorization.service.actor_ids_with_granular_permissions_on(
          actor_type:   actor_type,
          subject_type: subject_class,
          subject_ids:  subject_id,
          owner_ids:    subject_owner_id,
          permissions:  Array(resources),
          min_action:   min_action,
        )
      end
    end

    def installed_on_individual_repository_ids(min_action: :read, resource: nil, repository_ids: nil, organization: nil)
      T.bind(self, ProgrammaticActorTypes)

      return [] if organization && async_target.sync != organization

      science "installed_on_individual_repository_ids" do |e|
        e.use { installed_on_individual_repository_ids_control(min_action:, resource:, repository_ids:) }
        e.try { installed_on_individual_repository_ids_candidate(min_action:, resource:, repository_ids:) }

        e.compare do |control, candidate|
          control.sort == candidate.sort
        end
      end
    end

    def installed_on_individual_repository_ids_control(min_action:, resource:, repository_ids:)
      T.bind(self, ProgrammaticActorTypes)

      GitHub.tracer.in_span("integration_installable.installed_on_individual_repository_ids", kind: :internal) do |span|
        subject_types = if resource.present?
          "#{Repository::Resources::INDIVIDUAL_ABILITY_TYPE_PREFIX}/#{resource.downcase}"
        else
          Repository::Resources.subject_types.map { |st| "#{Repository::Resources::INDIVIDUAL_ABILITY_TYPE_PREFIX}/#{st}" }
        end

        repository_ids = Array(repository_ids)

        span.add_attributes(
          "gh.programmatic_actor.id" => ability_id,
          "gh.programmatic_actor.type" => ability_type,
          "gh.permission.subject_types" => Array(subject_types),
          "gh.permission.min_action" => Ability.actions[min_action],
          "gh.programmatic_actor_filter.repositories.count" => repository_ids.size
        )

        query = Permission
                  .where(
                    actor_id: ability_id,
                    actor_type: ability_type,
                    subject_type: subject_types
                  )
                  .where("action >= ?", Ability.actions[min_action])
                  .distinct

        if repository_ids.none?
          return query.pluck(:subject_id)
        end

        filtered_ids = T.let([], T::Array[Integer])

        repository_ids.in_groups_of(BATCH_SIZE, false) do |batched_ids|
          filtered_ids += query.where(subject_id: batched_ids).pluck(:subject_id)
        end

        filtered_ids
      end
    end

    def installed_on_individual_repository_ids_candidate(min_action:, resource:, repository_ids:)
      T.bind(self, ProgrammaticActorTypes)

      GitHub.tracer.in_span("integration_installable.installed_on_individual_repository_ids.candidate", kind: :internal) do |span|
        subject_types =
          if resource.present?
            ["#{Repository::Resources::INDIVIDUAL_ABILITY_TYPE_PREFIX}/#{resource.downcase}"]
          else
            Repository::Resources.subject_types.map { |st| "#{Repository::Resources::INDIVIDUAL_ABILITY_TYPE_PREFIX}/#{st}" }
          end

        repository_ids = Array(repository_ids)

        span.add_attributes(
          "gh.programmatic_actor.id" => ability_id,
          "gh.programmatic_actor.type" => ability_type,
          "gh.permission.subject_types" => subject_types,
          "gh.permission.min_action" => Permission.actions[min_action],
          "gh.programmatic_actor_filter.repositories.count" => repository_ids.size
        )

        query = Permission.where(
          actor_id: ability_id,
          actor_type: ability_type,
          subject_type: subject_types
        )

        if subject_types.many?
          query = query.distinct
          query = query.where("action >= ?", Permission.actions[min_action])
        elsif T.must(Permission.actions[min_action]) > T.must(Permission.actions[:read])
          query = query.where("action >= ?", Permission.actions[min_action])
        end

        if repository_ids.none?
          return query.pluck(:subject_id)
        end

        filtered_ids = T.let([], T::Array[Integer])

        repository_ids.in_groups_of(BATCH_SIZE, false) do |batched_ids|
          filtered_ids += query.where(subject_id: batched_ids).pluck(:subject_id)
        end

        filtered_ids
      end
    end

    def can_self_install?(target)
      T.bind(self, ProgrammaticActorTypes)

      return false unless self.target == target

      args = {
        priority: Ability.priorities[:direct],
        action: Ability.actions[:write],
        actor_id: ability_id,
        actor_type: ability_type,
        subject_types: [Repository.new.resources.administration.ability_type, User.new.repository_resources.administration.ability_type]
      }
      sql = Arel.sql <<-SQL, **args
        SELECT 1
        FROM permissions
        WHERE priority = :priority
        AND actor_id = :actor_id
        AND actor_type = :actor_type
        AND subject_type IN (:subject_types)
        AND action IN (:action)
        LIMIT 1
      SQL

      Permission.connection.select_value(sql).present?
    end

    # Internal: Indicates if installation is across all repositories or just selected ones.
    #
    # Returns a String.
    def repository_selection
      installed_on_all_repositories? ? "all" : "selected"
    end

    mixes_in_class_methods ClassMethods
  end
end
