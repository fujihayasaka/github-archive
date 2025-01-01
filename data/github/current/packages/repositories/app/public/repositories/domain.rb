# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain < GH::Domain::Base
    include GitHub::Memoizer
    include BadActorGate

    MAX_ROWS = 100_000
    MAX_INTERNAL_REPOSITORY_BATCH_SIZE = 25_000

    module Error
      class UnprocessableError < StandardError; end
    end

    unless GitHub.gitauth_host?
      decorate_with GH::Decorator::Memoization, only: [:by_qualified_name, :by_owner_and_repo_names, :active_by_id, :by_name_and_owner]
      decorate_with GH::Decorator::IdCaching, only: [:by_id]
    end

    accessor Repositories::Domain::Commits
    accessor Repositories::Domain::CustomProperties
    accessor Repositories::Domain::KeyLinks
    accessor Repositories::Domain::Pushes
    accessor Repositories::Domain::Topics
    accessor Repositories::Domain::Contents
    accessor Repositories::Domain::RepositoryNetworks, :networks

    # Given an organization and a user, return all of the org repos the user has access to
    sig do
      params(args: ByOrgMemberArgs)
      .returns(GH::Domain::Collection[IRepository])
      .checked(:always)
      .on_failure(:raise)
    end
    def by_org_member(args)
      check_domain_bad_actor_gate!(owner_id: args.organization.id, method_name: T.must(__method__))

      ff = GitHub.flipper[:programmatic_admin_experiment].enabled?(args.organization)

      control_finder = RepositoriesOrganizationFinder.new(
        owner: args.organization,
        viewer: args.user,
        repo_type: args.finder_type,
        unauthorized_viewer_organization_ids: args.unauthorized_organization_ids,
        permission: args.permission,
        programmatic_admin_experiment: ff
      )

      science "programmatic_admin_experiment" do |e|
        e.run_if { !ff && control_finder.viewer_can_access_all_org_repos? }
        e.compare_ordered_records
        e.try do
          candidate_finder = RepositoriesOrganizationFinder.new(
            owner: args.organization,
            viewer: args.user,
            repo_type: args.finder_type,
            unauthorized_viewer_organization_ids: args.unauthorized_organization_ids,
            permission: args.permission,
            programmatic_admin_experiment: true,
          )

          T.let(
            case args.pagination
            when GH::Pagination::Cursor
              RepositoryCursorCollection[IRepository].new(
                collection: candidate_finder.filter(**args.to_h),
                pagination: T.cast(args.pagination, GH::Pagination::Cursor),
                with_members: args.with_members,
                with_page_info: args.with_page_info,
                with_total_count: args.with_total_count,
                with_total_disk_usage: args.with_total_disk_usage
              )
            else
              GH::Pagination::Paginator.paginate(
                scope: T.cast(candidate_finder.filter(**args.to_h), ActiveRecord::Relation),
                pagination: args.pagination,
                sorts: args.sort.to_gh_sort(direction: args.direction),
                subquery_paginate: true
              )
            end,
            GH::Domain::Collection[IRepository]
          )
        end
        e.use do
          T.let(
            case args.pagination
            when GH::Pagination::Cursor
              RepositoryCursorCollection[IRepository].new(
                collection: control_finder.filter(**args.to_h),
                pagination: T.cast(args.pagination, GH::Pagination::Cursor),
                with_members: args.with_members,
                with_page_info: args.with_page_info,
                with_total_count: args.with_total_count,
                with_total_disk_usage: args.with_total_disk_usage
              )
            else
              GH::Pagination::Paginator.paginate(
                scope: T.cast(control_finder.filter(**args.to_h), ActiveRecord::Relation),
                pagination: args.pagination,
                sorts: args.sort.to_gh_sort(direction: args.direction),
                subquery_paginate: true
              )
            end,
            GH::Domain::Collection[IRepository]
          )
        end
      end
    end

    # Given an organization and a list of excluded repo ids, return all org repos not in the excluded list
    sig do
      params(
        organization_id: Integer,
        excluded_repo_ids: T.any(T::Array[Integer], T::Set[Integer]),
        pagination: GH::Pagination::Base,
        max_pages: Integer,
        public_only: T::Boolean
      )
      .returns(GH::Domain::Collection[IRepository])
    end
    def by_org_excluding(organization_id:, excluded_repo_ids:, pagination:, max_pages:, public_only: true)
      base_query = ::Repository
        .active
        .where(owner_id: organization_id)

      scope = base_query
        .where
        .not(id: excluded_repo_ids)

      scope = scope.public_scope if public_only

      collection = GH::Pagination::Paginator.paginate(
        scope:,
        pagination:,
        sorts: Repositories::SortBy::Id.to_gh_sort(direction: GH::Pagination::Sort::Direction::ASC),
        lazy_total_entries: -> { [base_query.count, max_pages].min },
        subquery_paginate: true
      )
      collection.iterable(self, T.must(__method__), organization_id:, excluded_repo_ids:, pagination:, max_pages:, public_only:)
    end

    # Given a string representing a repository's fully qualified name, returns the corresponding repository or nil.
    # Takes the current tenant into account as specified by GitHub::CurrentTenant when the owner's tenant
    # suffix is not included. When both are present, GitHub::CurrentTenant takes precedence.
    # Returns nil if the identified repository cannot be found.
    sig do
      params(qualified_name: String, search_redirects: T::Boolean).
      returns(T.nilable(IRepository)).
      checked(:always).on_failure(:raise)
    end
    def by_qualified_name(qualified_name, search_redirects: false)
      repo = ::Repository.nwo(qualified_name, nil, search_redirects:)
      repo.internal_repository if repo && repo.private?
      repo
    end

    # Given an owner name and a repository name, returns the corresponding repository or nil.
    # Takes the current tenant into account as specified by GitHub::CurrentTenant when the owner's tenant
    # suffix is not included. When both are present, GitHub::CurrentTenant takes precedence.
    # Returns nil if the identified repository cannot be found.
    sig do
      params(owner_name: T.nilable(String), repo_name: T.nilable(String), search_redirects: T::Boolean).
      returns(T.nilable(IRepository)).
      checked(:always).on_failure(:raise)
    end
    def by_owner_and_repo_names(owner_name, repo_name, search_redirects: false)
      repo = ::Repository.nwo(owner_name, repo_name, search_redirects:)
      repo.internal_repository if repo && repo.private?
      repo
    end

    # Given a owner_id and a list of repository ids, return the repository ids that are owned by the owner_id
    sig do
      params(
        owner_id: Integer,
        repo_ids_in: T.nilable(T::Array[Integer]),
        active_only: T::Boolean,
        public_only: T::Boolean
      ).returns(T::Array[Integer])
    end
    def repo_ids_by_owner(owner_id:, repo_ids_in:, active_only: true, public_only: true)
      return [] if repo_ids_in && repo_ids_in.empty?

      scope = repos_by_owner_scope(
        owner_id:,
        active_only:,
        visibility: public_only ? Repositories::RepositoryVisibility::Public : nil,
        locked: nil,
        network_roots: false
      )

      return scope.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ repositories.id")) if repo_ids_in.nil?

      where_id_in_asynchronously(scope, repository_ids: repo_ids_in)
    end

    # Given a list of org_ids return the active repository ids that are owned by the org_ids
    sig do
      params(
        org_ids: T::Array[Integer],
        include_repo_ids: T.nilable(T::Array[Integer]),
        exclude_archived: T::Boolean,
        private_only: T::Boolean,
        active_only: T::Boolean
      ).returns(T::Array[Integer])
    end
    def repo_ids_by_org_ids(org_ids:, include_repo_ids: nil, exclude_archived: false, private_only: false, active_only: true)
      # The index_repos_on_organization_id_active_public_and_parent_id index is required for the batching
      # query below to work correctly. That query relies on the ordering of the columns in the index to avoid
      # any need to sort results in memory.
      scope = ::Repository
        .from("repositories FORCE INDEX(index_repos_on_organization_id_active_public_and_parent_id)")
        .where(organization_id: org_ids)
        .order(:organization_id, :active, :public, :parent_id, :id)
        .limit(max_rows)

      cursor = T.let(nil, T.nilable(T::Array[T.any(T::Boolean, Integer)]))
      ids = []

      scope = scope.where(id: include_repo_ids) unless include_repo_ids.nil?
      scope = scope.where(maintained: true) if exclude_archived
      scope = scope.where(public: false) if private_only
      scope = scope.where(active: true) if active_only

      loop do
        if cursor.nil?
          batch_scope = scope
        else
          organization_id, active, public, parent_id, id = cursor
          batch_scope = scope.where(<<~SQL, { organization_id: organization_id, active: active, public: public, parent_id: parent_id, id: id })
            (
              organization_id > :organization_id
              OR
              (organization_id = :organization_id AND active > :active)
              OR
              (organization_id = :organization_id AND active = :active AND public > :public)
              OR
              (organization_id = :organization_id AND active = :active AND public = :public AND parent_id > COALESCE(:parent_id, 0))
              OR
              (organization_id = :organization_id AND active = :active AND public = :public AND parent_id <=> :parent_id AND id > :id)
            )
          SQL
        end

        batch_result = batch_scope.pluck(:organization_id, :active, :public, :parent_id, :id)
        ids.concat(batch_result.map { |row| row.last })

        break if batch_result.size < max_rows
        cursor = batch_result.last
      end

      ids
    end

    # Given a list of business_id return the internal repository ids that are owned by the business_ids
    sig do
      params(
        business_ids: T::Array[Integer],
        active_only: T::Boolean,
      ).returns(T::Array[Integer])
    end
    def internal_repo_ids_by_business_ids(business_ids:, active_only:)
      base_sql = Arel.sql(<<-SQL)
        SELECT ir.business_id, ir.repository_id, ir.id, repositories.active
        FROM repositories
      SQL

      cursor = T.let(nil, T.nilable(T::Array[Integer]))
      ids = []

      loop do
        if cursor.nil?
          sql = base_sql + Arel.sql(<<-SQL, business_ids: business_ids, max_rows: Arel.sql(max_internal_repository_batch_size.to_s))
            JOIN (
              SELECT business_id, repository_id, id
              FROM internal_repositories
              WHERE business_id IN (:business_ids)
              ORDER BY business_id, repository_id, id
              LIMIT :max_rows
            ) AS ir ON repositories.id = ir.repository_id
          SQL
        else
          business_id, repository_id, id = cursor
          sql = base_sql + Arel.sql(<<~SQL, business_ids: business_ids, business_id: business_id, repository_id: repository_id, id: id, max_rows: Arel.sql(max_internal_repository_batch_size.to_s))
            JOIN (
              SELECT business_id, repository_id, id
              FROM internal_repositories
              WHERE business_id IN (:business_ids)
              AND (
                business_id > :business_id
                OR
                (business_id = :business_id AND repository_id > :repository_id)
                OR
                (business_id = :business_id AND repository_id = :repository_id AND id > :id)
              )
              ORDER BY business_id, repository_id, id
              LIMIT :max_rows
            ) AS ir ON repositories.id = ir.repository_id
          SQL
        end

        batch_result = ApplicationRecord::Repositories.connection.select_all(sql).rows
        if active_only
          ids.concat batch_result.filter_map { |_, repo_id, _, active| repo_id if active }
        else
          ids.concat batch_result.map { |_, repo_id, _, _| repo_id }
        end

        break if batch_result.size < max_internal_repository_batch_size
        cursor = batch_result.last.first(3)
      end

      ids
    end

    # Given a list of owner_ids and a list of repository ids, return the repository ids that are owned by the owner_ids
    sig do
      params(
        owner_ids: T::Array[Integer],
        include_repo_ids: T.nilable(T::Array[Integer]),
        exclude_repo_ids: T.nilable(T::Array[Integer]),
        exclude_archived: T::Boolean,
        archived_only: T::Boolean,
        unlocked_only: T::Boolean,
        active_only: T::Boolean,
        visibility: T.nilable(Repositories::RepositoryVisibility),
        block: T.nilable(T.proc.params(arg0: T::Array[Integer]).void)
      ).returns(T.nilable(T::Array[Integer]))
    end
    def repo_ids_by_owners(
      owner_ids:,
      include_repo_ids: nil,
      exclude_repo_ids: nil,
      exclude_archived: false,
      archived_only: false,
      unlocked_only: false,
      active_only: false,
      visibility: nil,
      &block
    )

      raise Error::UnprocessableError.new("exclude_archived and archived_only are mutually exclusive") if exclude_archived && archived_only

      scope = ::Repository
        .from("repositories FORCE INDEX(index_repositories_on_owner_id_active_locked_parent_id_public)")
        .where(owner_id: owner_ids)
        .order(:owner_id, :active, :locked, :parent_id, :public, :id)
        .limit(max_rows)

      scope = scope.where.not(id: exclude_repo_ids) if exclude_repo_ids.present?
      scope = scope.where(id: include_repo_ids) unless include_repo_ids.nil?

      if visibility == RepositoryVisibility::Public
        scope = scope.where(public: true)
      elsif visibility == RepositoryVisibility::Private
        scope = scope.where(public: false)
      elsif visibility == RepositoryVisibility::Internal
        raise Error::UnprocessableError.new("internal visibility filtering is not supported")
      end

      scope = scope.where(active: true) if active_only

      scope = scope.where(archived_at: nil) if exclude_archived
      scope = scope.where.not(archived_at: nil) if archived_only

      scope = scope.where(locked: !unlocked_only) if unlocked_only

      cursor = T.let(nil, T.nilable(T::Array[T.any(T::Boolean, Integer)]))
      ids = T.let([], T::Array[Integer])

      loop do
        owner_id, active, locked, parent_id, public, id = cursor
        if cursor.nil?
          batch_scope = scope
        else
          batch_scope = scope.where(<<~SQL, { owner_id: owner_id, active: active, locked: locked, parent_id: parent_id, public: public, id: id })
            (
              owner_id > :owner_id
              OR
              (owner_id = :owner_id AND active > :active)
              OR
              (owner_id = :owner_id AND active = :active AND locked > :locked)
              OR
              (owner_id = :owner_id AND active = :active AND locked = :locked AND parent_id > COALESCE(:parent_id, 0))
              OR
              (owner_id = :owner_id AND active = :active AND locked = :locked AND parent_id <=> :parent_id AND public > :public)
              OR
              (owner_id = :owner_id AND active = :active AND locked = :locked AND parent_id <=> :parent_id AND public = :public AND id > :id)
            )
          SQL
        end
        batch_result = batch_scope.pluck(:owner_id, :active, :locked, :parent_id, :public, :id)

        id_batch = batch_result.map { |row| row.last }
        if block_given?
          id_batch.each_slice(MAX_REPOSITORY_ID_IN_CLAUSE_SIZE) { |id_batch_slice| yield id_batch_slice }
        else
          ids.concat(id_batch)
        end

        break if batch_result.size < max_rows
        cursor = batch_result.last
      end

      ids unless block_given?
    end

    # Given a list of owner_ids and a list of repository ids, return the repository ids that are not owned by the owner_ids
    sig do
      params(
        excluded_owner_ids: T::Array[Integer],
        repo_ids: T::Array[Integer],
      ).returns(T::Array[Integer])
    end
    def repo_ids_excluding_owners(excluded_owner_ids:, repo_ids:)
      ::Repository.where.not(owner_id: excluded_owner_ids).where(id: repo_ids).pluck(:id).to_a
    end

    # Given a owner_id and a list of repository ids, return the number of repository ids that are owned by the
    # owner_id
    sig do
      params(
        owner_id: Integer,
        repo_ids_in: T.nilable(T::Array[Integer]),
        active_only: T::Boolean,
        public_only: T::Boolean
      ).returns(Integer)
    end
    def repo_ids_by_owner_count(owner_id:, repo_ids_in:, active_only: true, public_only: true)
      return 0 if repo_ids_in && repo_ids_in.empty?

      scope = repos_by_owner_scope(
        owner_id:,
        active_only:,
        visibility: public_only ? Repositories::RepositoryVisibility::Public : nil,
        locked: nil,
        network_roots: false
      )

      return scope.count(:id) if repo_ids_in.nil?

      repo_ids_in = repo_ids_in.uniq

      return scope.where(id: repo_ids_in).count(:id) if use_sql_id_in_clause?(repo_ids_in)

      scope.batched_scope(:id, values: repo_ids_in, batch_size: MAX_REPOSITORY_ID_IN_CLAUSE_SIZE).execute { |scope| scope.async_count(:id) }.flat_map(&:value).sum
    end

    # Given an owner (User or Organization), return the number of repositories owned by the owner
    sig do
      params(
        owner_id: Integer,
        visibility: T.nilable(Repositories::RepositoryVisibility),
        locked: T.nilable(T::Boolean),
        network_roots: T::Boolean,
        limit: T.nilable(Integer)
      ).returns(Integer)
    end
    def total_active_count_by_owner(
      owner_id:,
      visibility: Repositories::RepositoryVisibility::Public,
      locked: nil,
      network_roots: false,
      limit: nil
    )
      scope = repos_by_owner_scope(owner_id:, active_only: true, visibility:, locked:, network_roots:)

      if !limit.nil?
        scope = scope.limit(limit)
      end

      scope.count
    end

    # Given an owner (User or Organization) and a type of repository (Repositories::RepositoryType), return a
    # page of owned repositories
    sig do
      params(
        owner: User,
        type: T.nilable(Repositories::RepositoryType),
        pagination: GH::Pagination::Offset,
        sort:  Repositories::SortBy,
        direction: GH::Pagination::Sort::Direction,
        public_only: T::Boolean
      ).returns(GH::Domain::Collection[IRepository])
    end
    def by_owner_and_type_for_actor(
      owner:,
      type:,
      pagination:,
      sort: Repositories::SortBy::Id,
      direction: GH::Pagination::Sort::Direction::ASC,
      public_only: true
    )
      order_by = { "field": sort, "direction": direction }

      finder = T.cast(
        Repositories::Public.finder_for(
          owner: owner,
          viewer: T.cast(actor, T.nilable(User)),
          permission: permission,
          repo_type: RepositoriesFinder::REPO_TYPE_DEFAULT,
          unauthorized_viewer_organization_ids: []
        ),
        RepositoriesFinder
      )
      scope = finder.filter(
        owner_affiliations: [:owned],
        privacy: public_only ? PlatformTypes::RepositoryType::PUBLIC.downcase : nil,
        order_by: order_by,
        type: type&.serialize&.downcase,
        remove_owner_in_clause: true
      )

      T.let(
        GH::Pagination::Paginator.paginate(
          scope:,
          pagination:,
          sorts: sort.to_gh_sort(direction: direction),
          subquery_paginate: true
        ),
        GH::Domain::Collection[IRepository]
      )
    end

    # Given an owner and the current actor (potentially anonymous), return the N most recently pushed repositories
    # the actor has access to
    sig do
      params(owner_id: Integer, limit: Integer)
      .returns(GH::Domain::Collection[IRepository])
      .checked(:always)
      .on_failure(:raise)
    end
    def recent_by_owner_for_actor(owner_id:, limit: 100)
      scope = repos_by_owner_scope(owner_id:, active_only: true, visibility: nil, locked: nil, network_roots: false)

      current_actor = actor

      # current_actor is logged in, viewing their own repos
      scope = if owner_id.present? && current_actor&.id.present? && owner_id == current_actor&.id
        scope
      # current_actor is logged in, viewing someone else's repos
      elsif current_actor && current_actor.id.present? && owner_id != current_actor.id
        accessible_repo_ids = Ability.where(
          subject_type: "Repository",
          actor_id: current_actor.id,
          actor_type: current_actor.ability_type,
          priority: Ability.priorities[:direct],
        ).pluck(:subject_id)

        scope.where("repositories.public = ? OR repositories.id IN (?)", true, accessible_repo_ids)
      # current_actor is logged out, viewing someone else's repos
      else
        scope.where("repositories.public = ?", true)
      end

      GH::Domain::Collection.new(
        scope.order(pushed_at: :desc, id: :desc)
        .limit(100)
        .to_a
      )
    end

    # Given an owner and the current actor, returns all the repository IDs
    # that are private, belong to the provided owner and the actor has access to
    sig { params(owner_id: T.any(Integer, T::Array[Integer]), resource: String).returns(T::Array[Integer]) }
    def private_repo_ids_by_owner_for_actor(owner_id:, resource:)
      return [] if actor.nil?

      # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
      private_repository_ids = T.cast(actor, User).associated_repository_ids(resource:)
      # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      private_repository_ids & ::Repository.private_scope.where(owner_id:).pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))
    end

    # Given a list of organization ids, return a hash of repo ID -> owning organization ID that is optionally
    # filtered by privacy, include forks, and excluded repo IDs
    sig do
      params(
        organization_ids: T.nilable(T::Array[Integer]),
        excluded_repo_ids: T::Array[Integer],
        privacy: T.nilable(Repositories::RepositoryPrivacy),
        include_forks: T::Boolean
      ).returns(T::Hash[Integer, Integer])
    end
    def org_repos_and_forks_by_privacy(organization_ids:, excluded_repo_ids:, privacy: nil, include_forks: false)
      scope = ::Repository.active
      scope = scope.where(organization_id: organization_ids)
      scope = scope.where(public: privacy.to_bool) if privacy
      scope = scope.where(parent_id: nil) unless include_forks
      scope = scope.where.not(id: excluded_repo_ids)

      Hash[scope.pluck(:id, :organization_id)]
    end

    # Given a repository id, returns the corresponding repository or nil. If the repository is deleted or soft-created
    # we also return nil.
    sig { params(id: Integer).returns(T.nilable(IRepository)).checked(:always).on_failure(:raise) }
    def active_by_id(id)
      # TODO(dmmatson): Once we prove id caching works we should do something like this which is more efficient
      # repo = T.cast(
      #   cache.fetch_by_id(id) do
      #     T.cast(by_id(id), T.nilable(GH::Domain::Cache::Cachable))
      #   end,
      #   T.nilable(IRepository)
      # )
      # return nil if repo.nil? || !repo.active?
      # repo

      ::Repository.find_by(id:, active: true)
    end

    # Given a repository id, returns the corresponding repository or nil.
    sig { params(id: Integer).returns(T.nilable(IRepository)).checked(:always).on_failure(:raise) }
    def by_id(id)
      ::Repository.find_by(id:)
    end

    # Given a list of repository ids, returns the corresponding repositories. If allow_deleted is true and any of the
    # ids correspond to deleted repositories, then the deleted repositories will be returned.
    sig do
      params(
        ids: T::Array[Integer],
        allow_deleted: T::Boolean,
        include_internal_repository: T::Boolean,
        batch_size: Integer
      ).returns(GH::Domain::Collection[IRepository])
    end
    def by_ids(ids, allow_deleted: false, include_internal_repository: false, batch_size: DEFAULT_REPOSITORY_ID_IN_CLAUSE_SIZE)
      log_list_size(ids.length, "repository_domain_by_ids")

      raise Error::UnprocessableError.new("batch_size must be <= #{MAX_REPOSITORY_ID_IN_CLAUSE_SIZE}") if batch_size > MAX_REPOSITORY_ID_IN_CLAUSE_SIZE

      repos = ::Repository.batched_scope(:id, values: ids, batch_size: batch_size) do |scope|
        scope = scope.active unless allow_deleted
        scope = scope.includes(:internal_repository) if include_internal_repository

        scope
      end
      GH::Domain::Collection.new(repos.to_a)
    end

    # Given a repository name and owner ID, returns the corresponding repository or nil.
    # Based off User#find_repo_by_name
    sig { params(name: String, owner_id: Integer).returns(T.nilable(IRepository)) }
    def by_name_and_owner(name:, owner_id:)
      return nil unless GitHub::UTF8.valid_unicode3?(name.to_s)

      Repository
          .eager_load(:network, :internal_repository)
          .where(owner_id: owner_id, active: true, name: name)
          .first
    end

    # Create a new repository.
    sig do
      params(
        repo_attributes: CreateRepositoryAttributes,

        # TODO: This is intentional tech debt until authorization is properly integrated into domains.
        # This data should be part of the domain's auth context, not part of the method arguments.
        # See https://github.com/github/monolith-platform/issues/424 for more.
        integration_context: T.untyped
      ).returns(GH::Result[IRepository]).checked(:always).on_failure(:raise)
    end
    def create(repo_attributes, integration_context: nil)
      current_actor = actor
      return GH::Result::Error::AccessDenied.new("Authentication required") if current_actor.nil?

      RepositoryCreation.new(repo_attributes:, integration_context:, actor: current_actor).execute
    end

    # Return repository ids for the current actor
    sig do
      params(
        unauthorized_org_ids: T::Array[Integer],
        include_org_owned_repos: T::Boolean,
        affiliations: T::Array[Symbol],
        visibility: String,
        sort: Repositories::SortBy,
        direction: GH::Pagination::Sort::Direction,
        since: T.nilable(Time),
        before: T.nilable(Time),
        list_private_repos: T.proc.returns(T::Boolean)
      ).returns(T::Array[Integer])
    end
    def repo_ids_for_actor(
      unauthorized_org_ids:,
      include_org_owned_repos:,
      affiliations:,
      visibility:,
      sort:,
      direction:,
      since:,
      before:,
      list_private_repos: -> { false }
    )
      current_user = T.cast(actor, User)

      check_domain_bad_actor_gate!(owner_id: current_user.id, method_name: T.must(__method__))

      # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
      total_repository_ids = T.let(current_user.associated_repository_ids(including: affiliations, include_indirect_forks: false), T::Array[Integer])
      # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      scope = Repository.active.filter_spam_for(current_user)

      if include_org_owned_repos
        if unauthorized_org_ids.any?
          total_repository_ids = where_id_in_asynchronously(
            scope.where("repositories.organization_id NOT IN (?) OR repositories.organization_id IS NULL", unauthorized_org_ids),
            repository_ids: total_repository_ids,
          )
        end
      else
        scope = scope.user_owned
      end

      if ProgrammaticActor::RepositoryFilter.applicable?(current_user)
        if visibility == Repository::PUBLIC_VISIBILITY
          scope = scope.public_scope
        else
          accessible_repo_ids = filter_for_programmatic_actor(scope.private_scope, repository_ids: total_repository_ids)

          if visibility == "all"
            possible_public_repo_ids = total_repository_ids - accessible_repo_ids
            accessible_repo_ids += where_id_in_asynchronously(scope.public_scope, repository_ids: possible_public_repo_ids)
          end

          total_repository_ids = accessible_repo_ids
        end
      else
        if visibility == Repository::PRIVATE_VISIBILITY
          scope = scope.private_scope
        elsif visibility == Repository::PUBLIC_VISIBILITY
          scope = scope.public_scope
        end

        scope = scope.public_scope unless list_private_repos.call
      end

      scope = scope.where(id: total_repository_ids)

      if since.present?
        scope = T.unsafe(scope).since(since.getlocal)
      end

      if before.present?
        scope = T.unsafe(scope).before(before.getlocal)
      end

      order_scope_by(scope, sort:, direction:).pluck(:id)
    end

    # Update the field on the repository with the latest count of how many users have starred it.
    sig { params(repository_id: Integer, count: Integer).returns(T::Boolean) }
    def update_stargazer_count(repository_id:, count:)
      repository = by_id(repository_id)

      return false unless repository
      return true if count == repository.stargazer_count

      # trigger callbacks with update
      T.cast(repository, Repository).update_attribute :stargazer_count, count # rubocop:todo GitHub/AvoidCast
    end

    # Given a list of owner ids (max), return the `limit` most recently pushed repositories
    # @param owner_ids [Array<Integer>] The list of owner ids to return repositories for.
    # @param limit [Integer] The maximum number of repositories to return.
    # @return [Array<Integer>] The list of repository ids that match the given owner ids.
    # @raise [UnprocessableError] if the owner_ids list is too large. max 30 elements
    # @raise [UnprocessableError] if the limit is too large. max 100 elements
    sig do
      params(
        owner_ids: T::Array[Integer],
        limit: Integer
      ).returns(T::Array[Integer])
    end
    def recent_by_owner_ids(owner_ids:, limit: 100)
      # Starting with max 30 owner_ids, 100 limit constraints
      # Because it is the first use case
      # And I don't want to leave these unbounded
      # But I think they could be a little higher if needed, let's discuss
      raise Error::UnprocessableError.new("owner_ids must be 30 or fewer elements") if owner_ids.size > 30
      raise Error::UnprocessableError.new("limit must be 100 or fewer") if limit > 100

      by_owner_union = owner_ids.map do |owner_id|
        scope = repos_by_owner_scope(
          owner_id:,
          active_only: true,
          visibility: nil,
          locked: nil,
          network_roots: false
        )
        "(#{scope.order(pushed_at: :desc, id: :desc).limit(limit).select(:id, :pushed_at).to_sql})"
      end.join(" UNION ")

      sql = Arel.sql(<<~SQL)
        SELECT id
        FROM (#{by_owner_union}) AS recent_repos
        ORDER BY pushed_at DESC, id DESC
        LIMIT #{limit}
      SQL

      ::Repository.connection.select_values(sql)
    end

    # Filter spam from an existing list of repository ids, and return the filtered list
    sig do
      params(
        current_user: T.nilable(User),
        repo_ids: T::Array[Integer],
        exclude_disabled_repos: T::Boolean
      ).returns(T::Array[Integer])
    end
    def filter_spam_from_repo_ids(current_user:, repo_ids:, exclude_disabled_repos: false)
      scope = Repository.filter_spam_for(current_user)
      scope = scope.where(disabled_at: nil) if exclude_disabled_repos

      where_id_in_asynchronously(scope, repository_ids: repo_ids)
    end

    # Given a repository id, returns the 300 most recent fork IDs
    sig do
      params(
        repo_id: Integer,
        limit: Integer,
        offset: Integer,
        sort:  Repositories::SortBy,
        direction: GH::Pagination::Sort::Direction,
        public_only: T::Boolean
      ).returns(T::Array[Integer])
    end
    def fork_ids_by_repo_id(
      repo_id:,
      limit: 30,
      offset: 0,
      sort: Repositories::SortBy::Id,
      direction: GH::Pagination::Sort::Direction::DESC,
      public_only: true
    )
      scope = ::Repository.where(parent_id: repo_id).active
      scope = scope.public_scope if public_only
      scope = order_scope_by(scope, sort:, direction:)

      scope.offset(offset).limit(limit).pluck(:id)
    end

    private

    sig do
      params(
        scope: ActiveRecord::Relation,
        sort: Repositories::SortBy,
        direction: GH::Pagination::Sort::Direction
      ).returns(ActiveRecord::Relation)
    end
    def order_scope_by(scope, sort:, direction:)
      scope.unscope(:order).order(GH::Pagination::Sort.to_order_by(sorts: sort.to_gh_sort(direction: direction)))
    end

    sig { params(scope: ActiveRecord::Relation, repository_ids: T::Array[Integer]).returns(T::Array[Integer]) }
    def where_id_in_asynchronously(scope, repository_ids:)
      return [] if repository_ids.empty?

      repo_ids_in = repository_ids.uniq

      return scope.where(id: repo_ids_in).pluck(:id) if use_sql_id_in_clause?(repo_ids_in)

      scope.batched_scope(:id, values: repo_ids_in, batch_size: MAX_REPOSITORY_ID_IN_CLAUSE_SIZE).execute { |scope| scope.async_pluck(:id) }.flat_map(&:value)
    end

    sig { params(scope: ActiveRecord::Relation, repository_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[Integer]]) }
    def where_id_in_asynchronously_with_owner_id(scope, repository_ids:)
      return {} if repository_ids.empty?

      repo_ids_in = repository_ids.uniq

      results = if use_sql_id_in_clause?(repo_ids_in)
        scope.where(id: repo_ids_in).pluck(:id, :owner_id)
      else
        scope.batched_scope(:id, values: repo_ids_in, batch_size: MAX_REPOSITORY_ID_IN_CLAUSE_SIZE).execute { |scope| scope.async_pluck(:id, :owner_id) }.flat_map(&:value)
      end

      results.group_by(&:second).transform_values { |v| v.map(&:first).flatten }
    end

    sig { params(filtered_repo_ids: T::Array[Integer]).returns(T::Boolean) }
    def use_sql_id_in_clause?(filtered_repo_ids)
      filtered_repo_ids.size <= MAX_REPOSITORY_ID_IN_CLAUSE_SIZE
    end

    sig do params(
      owner_id: Integer,
      active_only: T::Boolean,
      visibility: T.nilable(Repositories::RepositoryVisibility),
      locked: T.nilable(T::Boolean),
      network_roots: T::Boolean
      ).returns(ActiveRecord::Relation)
    end
    def repos_by_owner_scope(owner_id:, active_only:, visibility:, locked:, network_roots:)
      scope = ::Repository.where(owner_id: owner_id)
      scope = scope.active if active_only
      scope = case visibility
      when Repositories::RepositoryVisibility::Public
        scope.public_scope
      when Repositories::RepositoryVisibility::Private
        scope.private_scope
      when Repositories::RepositoryVisibility::Internal
        scope.joins(:internal_repository)
      else
        scope
      end

      if !locked.nil?
        scope = scope.where(locked: locked)
      end

      if network_roots
        scope = scope.network_roots
      end

      scope
    end

    sig { params(scope: ActiveRecord::Relation, repository_ids: T::Array[Integer]).returns(T::Array[Integer]) }
    def filter_for_programmatic_actor(scope, repository_ids: [])
      current_user = T.cast(actor, User)

      repository_ids_by_owner = load_repository_ids_by_owner(scope, repository_ids:)

      ProgrammaticActor::RepositoryFilter.perform_with_owner_and_repo_ids(
        actor: current_user,
        owner_and_repo_ids: repository_ids_by_owner,
      )
    end

    sig do
      params(
        scope: ActiveRecord::Relation,
        repository_ids: T::Array[Integer]
      ).returns(T::Hash[Integer, T::Array[Integer]])
    end
    def load_repository_ids_by_owner(scope, repository_ids: [])
      return {} if repository_ids.empty?

      where_id_in_asynchronously_with_owner_id(scope, repository_ids:)
    end

    sig { returns(Integer) }
    def max_rows
      MAX_ROWS
    end

    sig { returns(Integer) }
    def max_internal_repository_batch_size
      MAX_INTERNAL_REPOSITORY_BATCH_SIZE
    end
  end
end
