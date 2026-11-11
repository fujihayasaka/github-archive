# typed: true
# frozen_string_literal: true

module ProgrammaticActor
  module PermissionGrantable
    include Scientist

    BATCH_SIZE = 1000
    REPO_SELECTION_ALL = "all"
    REPO_SELECTION_SELECTED = "selected"

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
        feature_flag_enabled?(:cached_fgp_permissions, default: false) ? get_cached_permissions : permission_results
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

    # Public: Programmatic actors that support repository selection caching should
    # override this method to indicate they're compatible.
    sig { overridable.returns(T::Boolean) }
    def supports_repository_selection_cache?
      false
    end

    # Public: Programmatic actors that support repository selection caching should
    # override this method and return a String matching one of
    # REPO_SELECTION_ALL or REPO_SELECTION_SELECTED.
    #
    # Returns a String or nil if the selection has not been cached.
    sig { overridable.returns(T.nilable(String)) }
    def get_cached_repository_selection
      nil
    end

    # Public: Programmatic actors that support repository selection caching should
    # override this method, setting their cached repository selection to a
    # String matching one of REPO_SELECTION_ALL or REPO_SELECTION_SELECTED.
    #
    # Returns a String, the value argument passed.
    def set_cached_repository_selection(value = nil)
      value
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
    # skip_cache - An optional Boolean to skip checking the cached repository selection. Defaults to using the
    #              cache (skip_cache=false).
    #
    # Examples:
    #
    #   installed_on_all_repositories?(resource: "issues")
    #   installed_on_all_repositories?(resource: "pull_requests")
    #   installed_on_all_repositories?(min_action: :write, resource: "contents")
    #   installed_on_all_repositories?(skip_cache: true)
    #
    # Returns Boolean.
    def installed_on_all_repositories?(min_action: :read, resource: nil, skip_cache: false)
      arq = AllRepositoryAccessQueryRequest.new(grantable: T.cast(self, ProgrammaticActorTypes), min_action:, resource: resource&.to_s, skip_cache:, actor_type: actor_type)

      GitHub.dogstats.increment("permission_grantable.installed_on_all_repositories.can_use_cache", tags: arq.tags)

      if arq.read_repo_selection_from_cache?
        return GitHub.dogstats.distribution_time("permission_grantable.installed_on_all_repositories.from_cache", tags: arq.tags) do
          get_cached_repository_selection == REPO_SELECTION_ALL
        end
      end

      granted_all_repo_access = granted_all_repo_access_science_experiment(arq)

      if arq.can_use_repo_selection_cache?
        set_cached_repository_selection(
          repo_selection(granted_all_repo_access)
        )
      end

      granted_all_repo_access
    end

    private def granted_all_repo_access_science_experiment(arq)
      science "permission_grantable.granted_all_repo_access_via_permissions" do |e|
        e.use do
          granted_all_repo_access_via_permissions?(
            min_action: arq.min_action,
            subject_types: arq.all_repo_access_permission_subject_types_control,
            tags: arq.tags
          )
        end
        e.try do
          granted_all_repo_access_via_permissions?(
            min_action: arq.min_action,
            subject_types: arq.all_repo_access_permission_subject_types_candidate,
            tags: arq.tags
          )
        end
        e.compare { |use, try| use == try }
        e.context do
          {
            actor_id: arq.grantable.ability_id,
            actor_type: arq.actor_type,
            min_action: Ability.actions[arq.min_action],
            resource: arq.resource,
            metadata_default_enabled: arq.tags.include?("metadata_default_enabled:true"),
          }
        end
      end
    end

    class AllRepositoryAccessQueryRequest
      include GitHub::Memoizer

      sig { returns ProgrammaticActorTypes }
      attr_reader :grantable

      sig { returns String }
      attr_reader :actor_type

      sig { returns Symbol }
      attr_reader :min_action

      sig { returns(T.nilable(String)) }
      attr_reader :resource

      sig do
        params(
          grantable: ProgrammaticActorTypes,
          actor_type: String,
          min_action: Symbol,
          resource: T.nilable(String),
          skip_cache: T.nilable(T::Boolean),
        ).void
      end
      def initialize(grantable:, actor_type:, min_action: :read, resource: nil, skip_cache: false)
        @grantable = grantable
        @min_action = min_action
        @resource = resource
        @skip_cache = !!skip_cache
        @actor_type = actor_type
      end

      sig { returns T::Boolean }
      def skip_cache?
        @skip_cache
      end

      sig { returns T::Array[String] }
      memoize def tags
        [
          "min_action:#{min_action}",
          "actor_type:#{actor_type.underscore}",
          "metadata_default_enabled:#{FeatureFlag.vexi.enabled?(:use_metadata_default_installed_on_all_repositories, default: false)}",
          "can_use_cache:#{read_repo_selection_from_cache?}"
        ]
      end

      sig { returns T::Boolean }
      def read_repo_selection_from_cache?
        return false if skip_cache?

        can_use_repo_selection_cache?
      end

      sig { returns T::Boolean }
      memoize def can_use_repo_selection_cache?
        grantable.supports_repository_selection_cache? &&
          min_action == :read &&
          resource.nil? &&
          !grantable.frozen?
      end

      sig { returns T::Array[String] }
      memoize def all_repo_access_permission_subject_types_control
        if !resource.nil?
          ["#{Repository::Resources::ALL_ABILITY_TYPE_PREFIX}/#{resource&.downcase}"]
        else
          Repository::Resources.all_type_prefixed_subject_types
        end
      end

      sig { returns T::Array[String] }
      memoize def all_repo_access_permission_subject_types_candidate
        if !resource.nil?
          ["#{Repository::Resources::ALL_ABILITY_TYPE_PREFIX}/#{resource&.downcase}"]
        elsif  min_action == :read
          ["#{Repository::Resources::ALL_ABILITY_TYPE_PREFIX}/metadata"]
        else
          Repository::Resources.all_type_prefixed_subject_types
        end
      end
    end

    private def granted_all_repo_access_via_permissions?(min_action:, subject_types:, tags:)
      GitHub.dogstats.distribution_time("permission_grantable.installed_on_all_repositories", tags: tags) do
        T.bind(self, ProgrammaticActorTypes)

        subject_types = Array(subject_types)
        args = {
          actor_id:      ability_id,
          actor_type:    ability_type,
          min_action:    Ability.actions[min_action],
          subject_types: subject_types.length == 1 && metadata_default_ff_enabled? ? subject_types.first : subject_types,
        }

        sql =
          if metadata_default_ff_enabled?
            subject_condition =
              if subject_types.length > 1
                "subject_type IN (:subject_types)"
              else
                "subject_type = :subject_types"
              end

            Arel.sql(<<-SQL, **args)
              SELECT 1 as one
              FROM permissions
              WHERE actor_id = :actor_id
                AND actor_type = :actor_type
                AND #{subject_condition}
                AND action >= :min_action
              LIMIT 1
            SQL
          else
            Arel.sql(<<-SQL, **args)
              SELECT 1 as one
              FROM permissions
              WHERE actor_id = :actor_id
                AND actor_type = :actor_type
                AND subject_type IN (:subject_types)
                AND action >= :min_action
              LIMIT 1
            SQL
          end

        Permission.connection.select_values(sql).any?
      end
    end


    private def repo_selection(granted_all_repo_access = false)
      !!granted_all_repo_access ? REPO_SELECTION_ALL : REPO_SELECTION_SELECTED
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

      if FeatureFlag.vexi.enabled?(:skip_repository_ids_call_for_installs_on_all, default: false)
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
        if FeatureFlag.vexi.enabled?(:use_metadata_with_repository, default: false)
          with_resources_on(subject: repository, resources: :metadata)
        else
          with_resources_on(subject: repository, resources: Repository::Resources.subject_types)
        end
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

      GitHub.dogstats.distribution_time("permission_grantable.installed_on_individual_repository_ids") do
        return [] if organization && async_target.sync != organization

        GitHub.tracer.in_span("integration_installable.installed_on_individual_repository_ids", kind: :internal) do |span|
          subject_type_prefix = Repository::Resources::INDIVIDUAL_ABILITY_TYPE_PREFIX
          subject_types = []

          if !resource.nil?
            subject_types << "#{subject_type_prefix}/#{resource.downcase}"
          elsif min_action == :read
            subject_type = "#{subject_type_prefix}/metadata"
            if FeatureFlag.vexi.enabled?(:use_metadata_default_installed_on_individual_repository_ids, default: false) ||
              Permission.where(actor_id: ability_id, actor_type: ability_type, subject_type: subject_type).exists?
              # Check to see if the installation was granted metadata. Until backfill is complete
              # there are historical installations where we can't always rely on this being true.
              subject_types << subject_type
            end
          end

          if subject_types.empty?
            subject_types = Repository::Resources.subject_types.map { |st| "#{subject_type_prefix}/#{st}" }
          end

          repository_ids = Array(repository_ids)
          repository_ids.uniq! if repository_ids.any?

          span.add_attributes(
            "gh.programmatic_actor.id" => ability_id,
            "gh.programmatic_actor.type" => ability_type,
            "gh.permission.subject_types" => Array(subject_types),
            "gh.permission.min_action" => Ability.actions[min_action],
            "gh.programmatic_actor_filter.repositories.count" => repository_ids.size
          )

          query = Permission.where(actor_id: ability_id, actor_type: ability_type, subject_type: subject_types)

          # Only apply action >= ? for actions greater than read.
          if T.must(Ability.actions[min_action]) > T.must(Ability.actions[:read])
            query = query.where("action >= ?", Ability.actions[min_action])
          end

          science "permission_grantable.unique_subject_ids_in_ruby" do |e|
            e.compare_sorted_sequence

            e.use do
              control_query = query

              control_query = control_query.distinct if subject_types.many?

              if repository_ids.none?
                control_query.pluck(:subject_id)
              else
                filtered_ids = T.let([], T::Array[Integer])

                repository_ids.in_groups_of(BATCH_SIZE, false) do |batched_ids|
                  filtered_ids += control_query.where(subject_id: batched_ids).pluck(:subject_id)
                end

                filtered_ids
              end
            end

            e.try do
              candidate_query = query
              # skipping `query.distinct if subject_types.many?` and handling by calling `.uniq` in both branches of conditional
              if repository_ids.none?
                # calling `.uniq` here rather than using `distinct` in the sql query
                candidate_query.pluck(:subject_id).uniq
              else
                filtered_ids = T.let([], T::Array[Integer])

                repository_ids.in_groups_of(BATCH_SIZE, false) do |batched_ids|
                  filtered_ids += candidate_query.where(subject_id: batched_ids).pluck(:subject_id)
                end
                # calling `.uniq` here rather than using `distinct` in the sql query
                filtered_ids.uniq
              end
            end
          end
        end
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
    sig { params(skip_cache: T::Boolean).returns(String) }
    def repository_selection(skip_cache: false)
      return REPO_SELECTION_ALL if installed_on_all_repositories?(skip_cache: skip_cache)
      REPO_SELECTION_SELECTED
    end

    mixes_in_class_methods ClassMethods

    private

    def metadata_default_ff_enabled?
      FeatureFlag.vexi.enabled?(:use_metadata_default_installed_on_all_repositories, default: false)
    end
  end
end
