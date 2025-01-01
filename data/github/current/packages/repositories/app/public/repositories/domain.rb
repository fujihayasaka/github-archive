# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain < GH::Domain::Base
    extend T::Sig

    include GitHub::Memoizer
    include BadActorGate

    sig { params(caller_service: Symbol, actor: T.nilable(GH::Auth::Actor)).void }
    def initialize(caller_service, actor: nil) # rubocop:disable GitHub/DocumentationDomainMethod
      @caller_service = caller_service
      @actor = actor

      super(caller_service, actor:)
    end

    sig { returns(Repositories::Domain::KeyLink) }
    memoize def key_links # rubocop:disable GitHub/DocumentationDomainMethod
      Repositories::Domain::KeyLink.new(caller_service, actor: actor)
    end

    sig { returns(Repositories::Domain::Pushes) }
    memoize def pushes # rubocop:disable GitHub/DocumentationDomainMethod
      Repositories::Domain::Pushes.new(caller_service, actor: actor)
    end

    skip_decoration :key_links, :pushes

    # Given an organization and a user, return all of the org repos the user has access to
    sig do
      params(args: ByOrgMemberArgs)
      .returns(GH::Domain::Collection[IRepository])
      .checked(:always)
      .on_failure(:raise)
    end
    def by_org_member(args)
      check_domain_bad_actor_gate!(owner_id: T.must(args.organization.id), method_name: T.must(__method__))

      finder = RepositoriesOrganizationFinder.new(
        owner: args.organization,
        viewer: args.user,
        repo_type: args.finder_type,
        unauthorized_viewer_organization_ids: args.unauthorized_organization_ids,
        permission: args.permission
      )

      T.let(
        case args.pagination
        when GH::Pagination::Cursor
          RepositoryCursorCollection[IRepository].new(
            collection: finder.filter(**args.to_h),
            pagination: T.cast(args.pagination, GH::Pagination::Cursor)
          )
        else
          GH::Pagination::Paginator.paginate(
            scope: T.cast(finder.filter(**args.to_h), ActiveRecord::Relation),
            pagination: args.pagination,
            sorts: args.sort.to_gh_sort(direction: args.direction),
            subquery_paginate: true
          )
        end,
        GH::Domain::Collection[IRepository]
      )
    end

    # Given an organization and a list of excluded repo ids, return all org repos not in the excluded list
    sig do
      params(
        organization_id: Integer,
        excluded_repo_ids: T.any(T::Array[Integer], T::Set[Integer]),
        pagination: GH::Pagination::Offset,
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

      T.let(
        GH::Pagination::Paginator.paginate(
          scope:,
          pagination:,
          sorts: Repositories::SortBy::Id.to_gh_sort(direction: GH::Pagination::Sort::Direction::ASC),
          lazy_total_entries: -> { [base_query.count, max_pages].min },
          subquery_paginate: true
        ),
        GH::Domain::Collection[IRepository]
      )
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
      ::Repository.nwo(qualified_name, nil, search_redirects:)
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

      scope = repos_by_owner_scope(owner_id:, active_only:, public_only:)

      return scope.pluck(:id) if repo_ids_in.nil?

      repo_ids_in = repo_ids_in.uniq

      return scope.where(id: repo_ids_in).pluck(:id) if use_sql_id_in_clause?(repo_ids_in)

      scope.batched_scope(:id, values: repo_ids_in, batch_size: MAX_REPOSITORY_ID_IN_CLAUSE_SIZE).execute { |scope| scope.async_pluck(:id) }.flat_map(&:value)
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

      scope = repos_by_owner_scope(owner_id:, active_only:, public_only:)

      return scope.count(:id) if repo_ids_in.nil?

      repo_ids_in = repo_ids_in.uniq

      return scope.where(id: repo_ids_in).count(:id) if use_sql_id_in_clause?(repo_ids_in)

      scope.batched_scope(:id, values: repo_ids_in, batch_size: MAX_REPOSITORY_ID_IN_CLAUSE_SIZE).execute { |scope| scope.async_count(:id) }.flat_map(&:value).sum
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
      scope = repos_by_owner_scope(owner_id:, active_only: true, public_only: false)

      # actor is logged in, viewing their own repos
      scope = if owner_id.present? && actor&.id.present? && owner_id == actor&.id
        scope
      # actor is logged in, viewing someone else's repos
      elsif actor&.id.present? &&  owner_id != actor&.id
        accessible_repo_ids = Ability.where(
          subject_type: "Repository",
          actor_id: T.must(actor).id,
          actor_type: T.must(actor).ability_type,
          priority: Ability.priorities[:direct],
        ).pluck(:subject_id)

        scope.where("repositories.public = ? OR repositories.id IN (?)", true, accessible_repo_ids)
      # actor is logged out, viewing someone else's repos
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
      private_repository_ids & ::Repository.private_scope.where(owner_id:).ids
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

    # Given a repository id, returns the corresponding repository or nil. If allow_deleted is true and the id
    # corresponds to a deleted repository, then the deleted repository will be returned.
    sig { params(id: Integer, allow_deleted: T::Boolean).returns(T.nilable(IRepository)).checked(:always).on_failure(:raise) }
    def by_id(id, allow_deleted: false)
      allow_deleted ? ::Repository.find_by(id:) : ::Repository.find_by(id: id, active: true)
    end

    # Given a list of repository ids, returns the corresponding repositories. If allow_deleted is true and any of the
    # ids correspond to deleted repositories, then the deleted repositories will be returned.
    sig { params(ids: T::Array[Integer], allow_deleted: T::Boolean).returns(GH::Domain::Collection[IRepository]) }
    def by_ids(ids, allow_deleted: false)
      log_list_size(ids.length, "repository_domain_by_ids")
      repos = ::Repository.batched_scope(:id, values: ids) { |s| allow_deleted ? s : s.active }
      GH::Domain::Collection.new(repos.to_a)
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
      return GH::Result::Error::AccessDenied.new("Authentication required") if actor.nil?

      RepositoryCreation.new(repo_attributes:, integration_context:, actor: T.must(actor)).execute
    end

    private

    sig { params(filtered_repo_ids: T::Array[Integer]).returns(T::Boolean) }
    def use_sql_id_in_clause?(filtered_repo_ids)
      filtered_repo_ids.size <= MAX_REPOSITORY_ID_IN_CLAUSE_SIZE
    end

    sig do params(
      owner_id: Integer,
      active_only: T::Boolean,
      public_only: T::Boolean
      ).returns(ActiveRecord::Relation)
    end
    def repos_by_owner_scope(owner_id:, active_only:, public_only:)
      scope = ::Repository.where(owner_id: owner_id)
      scope = scope.active if active_only
      scope = scope.public_scope if public_only

      scope
    end
  end
end
