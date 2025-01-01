# typed: strict
# frozen_string_literal: true

require "gh/pagination/sort"

class RepositoriesOrganizationFinder
  extend T::Sig

  include Scientist

  PRIVATE_PRIVACY_VALUES = T.let(%w(private visibility).freeze, T::Array[String])
  FILTERS = T.let({
    active: 1,
    active_and_public: 2
  }, T::Hash[Symbol, Integer])

  sig { returns(Repositories::PlatformPermissionSwitch) }
  attr_reader :permission

  sig do
    params(
      owner: Organization,
      viewer: T.nilable(Users::IUser),
      unauthorized_viewer_organization_ids: T.nilable(T::Array[Integer]),
      permission: Repositories::PlatformPermissionSwitch,
      repo_type: String
    ).void
  end
  def initialize(
    owner:,
    viewer:,
    unauthorized_viewer_organization_ids:,
    permission:,
    repo_type: RepositoriesFinder::REPO_TYPE_DEFAULT
  )
    @owner = owner
    @viewer = viewer
    @unauthorized_viewer_organization_ids = unauthorized_viewer_organization_ids
    @permission = permission
    @repo_type = repo_type
  end

  sig do
    params(
      order_by: T.nilable(T.any(Platform::Inputs::RepositoryOrder, T::Hash[Symbol, Symbol])),
      type: T.nilable(T.any(PlatformTypes::RepositoryType, String)),
      privacy: T.nilable(String),
      visibility: T.nilable(String),
      affiliations: T.any(T.nilable(T::Array[Platform::Enums::RepositoryAffiliation]), T.nilable(T::Array[Symbol])),
      is_archived: T.nilable(T::Boolean),
      is_fork: T.nilable(T::Boolean),
      is_locked: T.nilable(T::Boolean),
      has_issues_enabled: T.nilable(T::Boolean),
      sponsorable_only: T.nilable(T::Boolean),
      default_affiliations: T.nilable(T::Array[Platform::Enums::RepositoryAffiliation]),
      filter_spam: T::Boolean
    ).returns(T.any(T::Array[Repository], ActiveRecord::Relation))
  end
  def filter(
    order_by: nil,
    type: nil,
    privacy: nil,
    visibility: nil,
    affiliations: nil,
    is_archived: nil,
    is_fork: nil,
    is_locked: nil,
    has_issues_enabled: nil,
    sponsorable_only: nil,
    default_affiliations: nil,
    filter_spam: true
  )
    # This is necessary due to some complexity in the repositories resolver.
    # `default_affiliations` can be overridden by subclasses.
    affiliations = affiliations || default_affiliations || RepositoriesFinder::DEFAULT_AFFILIATIONS

    relation = filter_repositories(
      sponsorable_only:,
      is_archived:,
      is_fork:,
      is_locked:,
      has_issues_enabled:,
      privacy:,
      visibility:,
      type:,
      affiliations:,
      filter_spam:
    )

    # If this is going through the API, chuck the private repos you can't see
    relation = determine_visibility(relation:, privacy: T.unsafe(privacy || visibility))

    fetch_repositories(relation:, order_by: sanitize_order_by(order_by:), privacy: T.unsafe(privacy || visibility))
  end

  sig do
    params(
      starting_scope: ActiveRecord::Relation,
      sort: Repositories::SortBy,
      direction: GH::Pagination::Sort::Direction,
      use_org_forks_experiment: T::Boolean,
      private_only: T::Boolean
    ).returns(ActiveRecord::Relation)
  end
  def repos_for_user_by_org(starting_scope:, sort:, direction:, use_org_forks_experiment:, private_only: false)
    scope = if viewer_can_access_all_org_repos?(use_org_forks_experiment:)
      starting_scope.where(owner_id: owner.id).where(organization_id: owner.id)
    else
      public_scope = public_scope(private_only:)
      private_scope = associated_repositories_scope

      member_scope = if !public_scope.nil? && !private_scope.nil?
        filter_scope(public_scope.or(private_scope), filter: starting_scope)
      elsif !public_scope.nil? && private_scope.nil?
        filter_scope(public_scope, filter: starting_scope)
      elsif public_scope.nil? && !private_scope.nil?
        filter_scope(private_scope, filter: starting_scope)
      else
        return Repository.none
      end

      member_scope.from("repositories USE INDEX (index_repos_on_organization_id_active_public_and_parent_id)")
    end

    scope = programmatic_scope(starting_scope:, current_scope: scope, private_only:)
    scope = scope.order(GH::Pagination::Sort.to_order_by(sorts: sort.to_gh_sort(direction:)))
    scope
  end

  private

  sig { returns(Organization) }
  attr_reader :owner

  sig { returns(T.nilable(Users::IUser)) }
  attr_reader :viewer

  sig { returns(T.nilable(T::Array[Integer])) }
  attr_reader :unauthorized_viewer_organization_ids

  sig { returns(String) }
  attr_reader :repo_type

  # Given a relation of Repositories, apply some filtering:
  # - Filter out spam
  # - Apply filters (if given) on privacy, affiliations, is_locked, language, type and query
  # - Filter out inactive repositories
  sig do
    params(
      sponsorable_only: T.nilable(T::Boolean),
      is_archived: T.nilable(T::Boolean),
      is_fork: T.nilable(T::Boolean),
      is_locked: T.nilable(T::Boolean),
      has_issues_enabled: T.nilable(T::Boolean),
      privacy: T.nilable(String),
      visibility: T.nilable(String),
      type: T.nilable(T.any(PlatformTypes::RepositoryType, String)),
      affiliations: T.nilable(T::Array[Platform::Enums::RepositoryAffiliation]),
      filter_spam: T::Boolean
    ).returns(ActiveRecord::Relation)
  end
  def filter_repositories(
    sponsorable_only:,
    is_archived:,
    is_fork:,
    is_locked:,
    has_issues_enabled:,
    privacy:,
    visibility:,
    type:,
    affiliations:,
    filter_spam:
  )
    relation = owner
      .org_repositories
      .active

    if filter_spam
      relation = relation.filter_spam_and_disabled_for(viewer)
    end

    relation = filter_by_unauthorized_organizations(relation, unauthorized_viewer_organization_ids:)
    relation = filter_by_privacy_and_visibility(relation, privacy:, visibility:)
    relation = filter_by_locked(relation, is_locked:)
    relation = filter_by_archived(relation, is_archived:)
    relation = filter_by_fork(relation, is_fork:)
    relation = filter_by_sponsorable(relation, sponsorable_only:)
    relation = filter_by_issues_enabled(relation, has_issues_enabled:)
    relation = filter_by_type(relation, type: type, privacy: privacy, affiliations: affiliations)

    relation
  end

  sig do
    params(
      relation: T.untyped,
      unauthorized_viewer_organization_ids: T.nilable(T::Array[Integer])
    ).returns(ActiveRecord::Relation)
  end
  def filter_by_unauthorized_organizations(relation, unauthorized_viewer_organization_ids:)
    if unauthorized_viewer_organization_ids.present?
      relation = relation.where.not(owner_id: unauthorized_viewer_organization_ids)
    else
      relation
    end
  end

  # Given a Repository scope, will return a modified scope that filters the
  # repositories according to the given type filter
  sig do
    params(
      relation: T.untyped,
      type: T.nilable(T.any(PlatformTypes::RepositoryType, String)),
      privacy: T.nilable(String),
      affiliations: T.nilable(T::Array[Platform::Enums::RepositoryAffiliation]),
    ).returns(ActiveRecord::Relation)
  end
  def filter_by_type(relation, type:, privacy:, affiliations:)
    return relation if T.unsafe(type).nil? && T.unsafe(privacy).nil?

    if type == PlatformTypes::RepositoryType::PUBLIC.downcase || privacy == PlatformTypes::RepositoryType::PUBLIC.downcase
      relation.public_scope
    elsif type == PlatformTypes::RepositoryType::PRIVATE.downcase || privacy == PlatformTypes::RepositoryType::PRIVATE.downcase
      relation.private_scope
    elsif type == "source"
      relation.not_archived_scope.where(parent_id: nil)
    elsif type == "fork"
      relation.not_archived_scope.forks
    elsif type == "mirror"
      relation.not_archived_scope.joins(:mirror)
    elsif type == "template"
      relation.not_archived_scope.templates
    elsif type == "archived"
      relation.archived_scope
    elsif type == "sponsorable"
      relation.with_sponsorable_owner
    else
      relation
    end
  end

  sig do
    params(
      relation: T.untyped,
      privacy: T.nilable(String),
      visibility: T.nilable(String),
    ).returns(ActiveRecord::Relation)
  end
  def filter_by_privacy_and_visibility(relation, privacy:, visibility:)
    if privacy == PlatformTypes::RepositoryType::PUBLIC.downcase || visibility == PlatformTypes::RepositoryVisibility::PUBLIC.downcase
      relation.public_scope
    elsif privacy == PlatformTypes::RepositoryType::PRIVATE.downcase
      relation.private_scope
    elsif visibility == PlatformTypes::RepositoryVisibility::PRIVATE.downcase
      relation.private_not_internal_scope
    elsif visibility == PlatformTypes::RepositoryVisibility::INTERNAL.downcase
      relation.internal_scope
    else
      relation
    end
  end

  sig do
    params(
      relation: T.untyped,
      is_locked: T.nilable(T::Boolean)
    ).returns(ActiveRecord::Relation)
  end
  def filter_by_locked(relation, is_locked:)
    case is_locked
    when true
      relation.locked_repos
    when false
      relation.unlocked_repos
    else
      relation
    end
  end

  sig do
    params(
      relation: T.untyped,
      is_archived: T.nilable(T::Boolean)
    ).returns(ActiveRecord::Relation)
  end
  def filter_by_archived(relation, is_archived:)
    case is_archived
    when true
      relation.archived_scope
    when false
      relation.not_archived_scope
    else
      relation
    end
  end

  sig do
    params(
      relation: T.untyped,
      is_fork: T.nilable(T::Boolean)
    ).returns(ActiveRecord::Relation)
  end
  def filter_by_fork(relation, is_fork:)
    case is_fork
    when true
      relation.where.not(parent_id: nil)
    when false
      relation.where(parent_id: nil)
    else
      relation
    end
  end

  sig do
    params(
      relation: T.untyped,
      sponsorable_only: T.nilable(T::Boolean)
    ).returns(ActiveRecord::Relation)
  end
  def filter_by_sponsorable(relation, sponsorable_only:)
    if sponsorable_only && GitHub.sponsors_enabled?
      relation.with_sponsorable_owner
    else
      relation
    end
  end

  sig do
    params(
      relation: T.untyped,
      has_issues_enabled: T.nilable(T::Boolean)
    ).returns(ActiveRecord::Relation)
  end
  def filter_by_issues_enabled(relation, has_issues_enabled:)
    if has_issues_enabled.present?
      relation = relation.where(has_issues: has_issues_enabled)
    else
      relation
    end
  end

  # Given a Repository scope, will return a modified scope that filters the
  # repositories according to the given privacy filter
  sig { params(relation: T.untyped, privacy: T.nilable(String)).returns(ActiveRecord::Relation) }
  def determine_visibility(relation:, privacy:)
    permission_switch = permission.permission!

    return relation.public_scope if privacy == "public"
    if (permission_switch.present? && permission_switch.async_can_list_private_repos?(owner).sync) || permission_switch.nil?
      return relation
    end

    case privacy
    when "private", "internal"
      Repository.none
    else
      relation.public_scope
    end
  end

  sig do
    params(
      relation: T.untyped,
      order_by: T.nilable(T.any(Platform::Inputs::RepositoryOrder, T::Hash[Symbol, Symbol])),
      privacy: T.nilable(String)
    ).returns(T.any(ActiveRecord::Relation, Platform::ArrayWrapper))
  end
  def fetch_repositories(relation:, order_by:, privacy:)
    if fetch_template_repositories?
      repos = owner.repository_templates_for(viewer, scope: relation)
      Platform::ArrayWrapper.new(repos)
    elsif fetch_watched_repositories?
      ids = Platform::Helpers::WatchingQuery.new(viewer, owner).fetch!.to_a

      result = ids.each_slice(Platform::Resolvers::WatchedRepositories::BATCH_SIZE).with_object(Array.new) do |repo_ids, list|
        list.concat(::Repository.where(id: repo_ids).merge(relation))
      end
      result = sort_repo_list(repos: result, order_by:)

      Platform::ArrayWrapper.new(result)
    else
      owner.async_business.then do
        sorts = case order_by&.dig(:field)
        when "created_at"
          Repositories::SortBy::CreatedAt
        when "updated_at"
          Repositories::SortBy::UpdatedAt
        when "pushed_at"
          Repositories::SortBy::PushedAt
        when "name"
          Repositories::SortBy::Name
        when "watcher_count"
          Repositories::SortBy::WatcherCount
        else
          Repositories::SortBy::Id
        end
        direction = GH::Pagination::Sort::Direction.from_string(order_by&.dig(:direction))

        if viewer && T.cast(viewer, User).governed_by_oauth_application_policy? && \
          owner.adminable_by?(viewer) && \
          GitHub.flipper[:experiment_org_forks].enabled?(owner.business) && \
          oauth_app_can_access_all_org_repos?

          next science "org_forks_experiment" do |e|
            e.use do
              repos_for_user_by_org(
                starting_scope: relation,
                sort: sorts,
                direction: direction,
                private_only: PRIVATE_PRIVACY_VALUES.include?(privacy),
                use_org_forks_experiment: false
              ).load
            end
            e.try do
              repos_for_user_by_org(
                starting_scope: relation,
                sort: sorts,
                direction: direction,
                private_only: PRIVATE_PRIVACY_VALUES.include?(privacy),
                use_org_forks_experiment: true
              ).load
            end
            e.compare_ordered_records
          end
        end

        repos_for_user_by_org(
          starting_scope: relation,
          sort: sorts,
          direction: direction,
          private_only: PRIVATE_PRIVACY_VALUES.include?(privacy),
          use_org_forks_experiment: GitHub.flipper[:use_org_forks_experiment].enabled?(owner.business)
        )
      end.sync
    end
  end

  sig { returns(T::Boolean) }
  def fetch_watched_repositories?
    @repo_type == RepositoriesFinder::REPO_TYPE_WATCHED
  end

  sig { returns(T::Boolean) }
  def fetch_template_repositories?
    @repo_type == RepositoriesFinder::REPO_TYPE_TEMPLATE
  end

  # Apply the specified ordering to the overall list, in case the repositories were fetched
  # in batches with only each batch being ordered in SQL
  #
  # Necessary for WatchedRepositories
  sig { params(repos: T.untyped, order_by: T.nilable(T.any(Platform::Inputs::RepositoryOrder, T::Hash[Symbol, Symbol]))).returns(T.untyped) }
  def sort_repo_list(repos:, order_by:)
    if order_by
      # This column has been marked for rename. We need to refer to the new name here as this
      # accesses the model's attribute, not the database column. This can go when the rename
      # is complete.
      field = order_by[:field] == "watcher_count" ? "stargazer_count" : order_by[:field]
      repos = repos.sort_by { |repo| repo[field].to_s }
      repos = repos.reverse if order_by[:direction] == "DESC"
    end

    repos
  end

  # Necessary to prevent potential SQL injection when not using Platform::Inputs
  sig do
    params(
      order_by: T.nilable(T.any(Platform::Inputs::RepositoryOrder, T::Hash[Symbol, Symbol]))
    ).returns(T.nilable(T.any(Platform::Inputs::RepositoryOrder, T::Hash[Symbol, Symbol])))
  end
  def sanitize_order_by(order_by:)
    return order_by unless order_by && !order_by.is_a?(Platform::Inputs::RepositoryOrder)

    order_by_field = order_by[:field]&.to_s&.upcase
    order_by_field = "STARGAZERS" if order_by_field == "WATCHER_COUNT"
    if order_by_field && field_value = Platform::Enums::RepositoryOrderField.values[order_by_field]&.value
      order_by[:field] = field_value
    else
      order_by.delete(:field)
    end

    order_by_direction = order_by[:direction]&.to_s&.upcase
    if order_by_direction && direction_value = Platform::Enums::OrderDirection.values[order_by_direction]&.value
      order_by[:direction] = direction_value
    else
      order_by.delete(:direction)
    end

    order_by = nil if order_by.length != 2

    order_by
  end

  REPO_INTERSECTION_THRESHOLD = T.let(Repositories::AssociatedRepositoriesDependency::AssociatedRepositories::RUBY_INTERSECTION_THRESHOLD * 2, Integer)

  sig { params(private_only: T::Boolean).returns(T.untyped) }
  def public_scope(private_only:)
    if !private_only
      Repository.active
        .where(organization_id: owner.id)
        .public_scope
    else
      nil
    end
  end

  sig { returns(T.untyped) }
  def associated_repositories_scope
    team_and_internal_repo_ids = if viewer
      user = T.cast(viewer, User)
      repo_ids_with_team_membership = if GitHub.flipper[:org_scoped_ari].enabled?(owner) || GitHub.flipper[:org_scoped_ari].enabled?(user)
        org_scoped_repo_ids_with_team_membership
      else
        unscoped_repo_ids_with_team_membership
      end

      if owner.supports_internal_repositories?
        internal_repos_ids = owner.org_repositories
          .left_joins(:internal_repository)
          .where(internal_repository: { business_id: user.business_ids })
          .ids
      else
        internal_repos_ids = []
      end

      [repo_ids_with_team_membership + internal_repos_ids].flatten.uniq
    else
      []
    end

    if !team_and_internal_repo_ids.empty?
      owner.org_repositories.active.where(id: team_and_internal_repo_ids)
    else
      nil
    end
  end

  sig { params(starting_scope: ActiveRecord::Relation, current_scope: ActiveRecord::Relation, private_only: T::Boolean).returns(ActiveRecord::Relation) }
  def programmatic_scope(starting_scope:, current_scope:, private_only:)
    if ProgrammaticActor::RepositoryFilter.applicable?(viewer)
      accessible_repository_ids = ProgrammaticActor::RepositoryFilter.perform(
        actor: viewer,
        repository_ids: current_scope.pluck(:id)
      )
      if private_only
        starting_scope.where(owner: owner)
          .where(id: accessible_repository_ids)
      else
        programmatic_scope = starting_scope.where(owner: owner)
        if accessible_repository_ids.empty?
          programmatic_scope.where("repositories.public = ?", true)
        else
          programmatic_scope.where("repositories.public = ? OR repositories.id IN (?)", true, accessible_repository_ids)
        end
      end
    else
      current_scope
    end

  end

  sig { params(scope: ActiveRecord::Relation, filter: T.nilable(ActiveRecord::Relation)).returns(ActiveRecord::Relation) }
  def filter_scope(scope, filter: nil)
    filter ? scope.merge(filter) : scope
  end

  sig { returns(T::Array[Integer]) }
  def unscoped_repo_ids_with_team_membership
    # The current user may be allowed to see this org's private repos if those repos are private forks
    # of repos owned by an org the user is an admin of. If this org has no private forks, there's
    # no need to check for this case, and if the user is an admin of this org they'll be able to
    # see those repos without a special oopfs check via their admin access.
    include_oopfs = !(owner.adminable_by?(viewer) || owner.repositories.forks.private_scope.none?)

    organization_ids = Repository.active.owned_by(owner).ids

    if organization_ids.size > REPO_INTERSECTION_THRESHOLD
      T.cast(viewer, User).associated_repository_ids(
        including: [:direct, :indirect],
        repository_ids: organization_ids,
        include_oopfs: include_oopfs,
      )
    else
      T.cast(viewer, User).associated_repository_ids( # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        including: [:direct, :indirect],
        include_oopfs: include_oopfs,
      ) & organization_ids
    end
  end

  sig { returns(T::Array[Integer]) }
  def org_scoped_repo_ids_with_team_membership
    # The user may be allowed to see this org's private repos if those repos are private forks
    # of repos owned by an org the user is an admin of. Pass this organization to
    # User#associated_repository_ids so results can be scoped more efficiently.
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    T.cast(viewer, User).associated_repository_ids(including: [:direct, :indirect], organization: owner)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
  end

  sig { params(use_org_forks_experiment: T::Boolean).returns(T::Boolean) }
  def viewer_can_access_all_org_repos?(use_org_forks_experiment: false)
    return false if viewer.nil?
    # if the current organization or the organization owner of the private fork
    # restricts access to oauth applications, then we can't rely only in the viewer
    # being an admin of the organization to allow access to all repositories
    # owned by the organization.
    if use_org_forks_experiment
      return false unless owner.adminable_by?(viewer)
      return true unless T.cast(viewer, User).governed_by_oauth_application_policy?

      return oauth_app_can_access_all_org_repos?
    end

    return false if T.cast(viewer, User).governed_by_oauth_application_policy?

    owner.adminable_by?(viewer)
  end

  sig { returns(T::Boolean) }
  def oauth_app_can_access_all_org_repos?
    user = T.cast(viewer, User)
    app = user.oauth_application

    return false unless app.oap_exempt?
    return false unless owner.allows_oauth_application?(user.oauth_application)
    return false if org_has_external_private_forks?

    true
  end

  sig { returns(T::Boolean) }
  def org_has_external_private_forks?
    sql = Arel.sql <<~SQL, organization_id: owner.id
      (
        SELECT 1
        FROM `repositories`
        INNER JOIN `repositories` AS `root` ON `root`.source_id = repositories.source_id
        WHERE root.parent_id IS NULL
        AND   root.public = 0
        AND   root.organization_id != repositories.organization_id
        AND   repositories.organization_id = (:organization_id)
        AND   repositories.parent_id IS NOT NULL
        LIMIT 1
      ) UNION ALL (
        SELECT 1
        FROM `repositories`
        INNER JOIN `repositories` AS `root` ON `root`.source_id = repositories.source_id
        WHERE root.parent_id IS NULL
        AND   root.public = 0
        AND   root.organization_id IS NOT NULL
        AND   root.organization_id != repositories.organization_id
        AND   repositories.owner_id = (:organization_id)
        AND   repositories.parent_id IS NOT NULL
        LIMIT 1
      )
    SQL
    Repository.connection.select_all(sql).any?
  end
end
