# typed: true
# frozen_string_literal: true

class RepositoriesFinder
  DEFAULT_AFFILIATIONS = [:owned, :direct].freeze
  REPO_TYPE_DEFAULT = "default"
  REPO_TYPE_WATCHED = "watched"
  REPO_TYPE_TEMPLATE = "template"
  LARGE_IDS_THRESHOLD = 1_000

  attr_reader :permission

  def initialize(
    owner:,
    viewer:,
    unauthorized_viewer_organization_ids:,
    permission:,
    repo_type: REPO_TYPE_DEFAULT
  )
    @owner = owner
    @viewer = viewer
    @unauthorized_viewer_organization_ids = unauthorized_viewer_organization_ids
    @permission = permission
    @repo_type = repo_type
    @ari_cache = {}
  end

  def filter(
    order_by: nil,
    type: nil,
    privacy: nil,
    visibility: nil,
    affiliations: nil,
    owner_affiliations:,
    is_archived: nil,
    is_fork: nil,
    is_locked: nil,
    has_issues_enabled: nil,
    sponsorable_only: nil,
    default_affiliations: nil,
    cursor: nil,
    check_large_scope: false,
    remove_duplicate_in_clause: false,
    remove_owner_in_clause: false
  )
    async_filter(
      order_by: order_by,
      type: type,
      privacy: privacy,
      visibility: visibility,
      affiliations: affiliations,
      owner_affiliations: owner_affiliations,
      is_archived: is_archived,
      is_fork: is_fork,
      has_issues_enabled: has_issues_enabled,
      is_locked: is_locked,
      sponsorable_only: sponsorable_only,
      default_affiliations: default_affiliations,
      cursor: cursor,
      check_large_scope: check_large_scope,
      remove_duplicate_in_clause: remove_duplicate_in_clause,
      remove_owner_in_clause: remove_owner_in_clause,
    ).sync
  end

  def async_filter(
    order_by: nil,
    type: nil,
    privacy: nil,
    visibility: nil,
    affiliations: nil,
    owner_affiliations:,
    is_archived: nil,
    is_fork: nil,
    has_issues_enabled: nil,
    is_locked: nil,
    sponsorable_only: nil,
    default_affiliations: nil,
    cursor: nil,
    check_large_scope: false,
    remove_duplicate_in_clause: false,
    remove_owner_in_clause: false
  )
    filtering_by_affiliations = affiliations.present?
    # This is necessary due to some complexity in the repositories resolver.
    # `default_affiliations` can be overridden by subclasses.
    affiliations = affiliations || default_affiliations || DEFAULT_AFFILIATIONS

    # Necessary to prevent potential SQL injection when not using Platform::Inputs
    if order_by && !order_by.is_a?(Platform::Inputs::RepositoryOrder)
      if field_value = Platform::Enums::RepositoryOrderField.values[order_by[:field]&.to_s&.upcase]&.value
        order_by[:field] = field_value
      else
        order_by.delete(:field)
      end

      if direction_value = Platform::Enums::OrderDirection.values[order_by[:direction]&.to_s&.upcase]&.value
        order_by[:direction] = direction_value
      else
        order_by.delete(:direction)
      end

      order_by = nil if order_by.length != 2
    end

    list_repositories(
      privacy: privacy,
      visibility: visibility,
      order_by: order_by,
      affiliations: affiliations,
      owner_affiliations: owner_affiliations,
      is_archived: is_archived,
      is_fork: is_fork,
      has_issues_enabled: has_issues_enabled,
      is_locked: is_locked,
      type: type,
      filtering_by_affiliations: filtering_by_affiliations,
      sponsorable_only: sponsorable_only,
      cursor: cursor,
      check_large_scope: check_large_scope,
      remove_duplicate_in_clause: remove_duplicate_in_clause,
      remove_owner_in_clause: remove_owner_in_clause
    )
  end

  private

  attr_reader :owner, :viewer, :unauthorized_viewer_organization_ids, :repo_type, :cursor

  def list_repositories(
    order_by:,
    type:,
    has_issues_enabled:,
    privacy:,
    visibility:,
    affiliations:,
    owner_affiliations:,
    is_archived:,
    is_fork:,
    is_locked:,
    filtering_by_affiliations:,
    sponsorable_only:,
    cursor:,
    check_large_scope:,
    remove_duplicate_in_clause:,
    remove_owner_in_clause:
  )
    base_query = build_base_query
    relation = filter_repositories(base_query, order_by: order_by,
                                   is_archived: is_archived, is_fork: is_fork, affiliations: affiliations,
                                   sponsorable_only: sponsorable_only, owner_affiliations: owner_affiliations,
                                   is_locked: is_locked, privacy: privacy, visibility: visibility, has_issues_enabled: has_issues_enabled,
                                   filtering_by_affiliations: filtering_by_affiliations,
                                   remove_duplicate_in_clause: remove_duplicate_in_clause)
    relation = filter_repos_by_type(relation, type: type, privacy: privacy, affiliations: affiliations)
    # if this is going through the API, chuck the private repos you can't see
    relation = determine_visibility(relation, privacy || visibility)
    # Fetch repositories from the database; return an AR::Relation or Array of Repositories
    Promise.new.fulfill(
      fetch_repositories(
        owner_affiliations,
        scope: relation,
        order_by: order_by,
        cursor: cursor,
        check_large_scope: check_large_scope,
        remove_owner_in_clause: remove_owner_in_clause
      )
    )
  end

  def associated_repository_ids(affiliations)
    return [] unless viewer.present?

    cache_associated_repository_ids(viewer.id, affiliations) do
      # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
      repo_ids = viewer.associated_repository_ids(including: affiliations)
      # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded

      next repo_ids if repo_ids.empty?
      next repo_ids unless ProgrammaticActor::RepositoryFilter.applicable?(viewer)

      accessible_repo_ids = ProgrammaticActor::RepositoryFilter.perform(
        actor: viewer,
        repository_ids: repo_ids,
      )

      Repository.where(id: repo_ids).public_scope.pluck(:id) | accessible_repo_ids
    end
  end

  def build_base_query
    if owner.is_a?(Repository)
      owner.forks
    elsif owner.is_a?(RepositoryNetwork) || owner.is_a?(Topic)
      owner.repositories
    else
      Repository
    end
  end

  # Given a relation of Repositories, apply some filtering:
  # - Filter out spam
  # - Apply filters (if given) on privacy, affiliations, is_locked, language, type and query
  # - Filter out inactive repositories
  #
  # Returns a new ActiveRecord::Relation
  def filter_repositories(
    relation,
    order_by:,
    affiliations:,
    sponsorable_only:,
    owner_affiliations:,
    is_archived:,
    is_fork:,
    is_locked:,
    has_issues_enabled:,
    privacy:,
    visibility:,
    filtering_by_affiliations:,
    remove_duplicate_in_clause:
  )
    relation = relation.filter_spam_and_disabled_for(viewer)

    case is_locked
    when true
      relation = relation.locked_repos
    when false
      relation = relation.unlocked_repos
    end

    if unauthorized_viewer_organization_ids.present?
      relation = relation.where("repositories.owner_id NOT IN (?)", unauthorized_viewer_organization_ids)
    end

    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    filtered_repo_ids = associated_repository_ids(affiliations)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded

    scope =
      if privacy == PlatformTypes::RepositoryType::PUBLIC.downcase || visibility == PlatformTypes::RepositoryVisibility::PUBLIC.downcase
        :public_scope
      elsif privacy == PlatformTypes::RepositoryType::PRIVATE.downcase
        :private_scope
      elsif visibility == PlatformTypes::RepositoryVisibility::PRIVATE.downcase
        :private_not_internal_scope
      elsif visibility == PlatformTypes::RepositoryVisibility::INTERNAL.downcase
        :internal_scope
      end

    if scope
      relation = filter_by_owner_type(relation: relation, scope: scope, filtered_repo_ids: filtered_repo_ids)
    else
      case owner
      when User, Repository, RepositoryNetwork
        if filtering_by_affiliations
          unless remove_duplicate_in_clause && owner == viewer && owner_affiliations.sort == affiliations.sort
            relation = relation.where(["(repositories.id IN (?))", filtered_repo_ids])
          end
        else
          relation = relation.where(["repositories.public = true OR (repositories.id IN (?))", filtered_repo_ids])
        end
      end
    end

    if owner.is_a?(User) && owner_affiliations.include?(:indirect)
      # filter out private org memberships for this user
      # - Get the list of _visible_ orgs
      # - Get the list of all of the orgs the viewer belongs to
      # - Get the list of _all_ orgs
      # - Get the difference of the two; those are the hidden orgs
      # - Remove repos that belong to hidden orgs AND are not contributed-to.
      all_org_ids = owner.organizations.pluck("id")
      if all_org_ids.any?
        visible_org_ids = Organization.connection.select_rows(Arel.sql(<<-SQL, user_id: owner.id))
          SELECT organization_id FROM public_org_members
          WHERE user_id = :user_id
        SQL
        visible_org_ids.flatten!

        # Find the orgs of the viewer, to allow those repos to be seen
        viewer_org_ids = viewer&.organizations&.pluck("id") || []

        # Hide away the organizations that are either private or the viewer does not
        # have access to
        hidden_org_ids = all_org_ids - (visible_org_ids + viewer_org_ids)
        if hidden_org_ids.any?
          # `hidden_org_ids` may filter out repos that the user contributed to.
          # But if `:direct` is also present, we should also include
          # repos where this user contributed, even if their org membership is hidden
          contributed_repo_override_ids = cache_associated_repository_ids(owner.id, [:direct]) do
            if owner_affiliations.include?(:direct)
              owner.associated_repository_ids(including: [:direct])
            else
              []
            end
          end
          relation = relation.where("
                repositories.organization_id IS NULL
            OR  repositories.organization_id NOT IN(?)
            OR  repositories.id IN(?)
          ", hidden_org_ids, contributed_repo_override_ids)
        end
      end
    end
    case is_archived
    when true
      relation = relation.archived_scope
    when false
      relation = relation.not_archived_scope
    end
    case is_fork
    when true
      relation = relation.where("repositories.parent_id IS NOT NULL")
    when false
      relation = relation.where("repositories.parent_id IS NULL")
    end

    case has_issues_enabled
    when true
      relation = relation.where("repositories.has_issues=TRUE")
    when false
      relation = relation.where("repositories.has_issues=FALSE")
    end

    if order_by
      relation = relation.order(order_by[:field] => order_by[:direction])
    end

    relation = relation.with_sponsorable_owner if sponsorable_only && GitHub.sponsors_enabled?
    relation.active
  end

  # Internal: Given an AR Relation, scope name and an array of filtered repo IDs (optional),
  # this method applies the correct filtering based on the owner type and returns an AR Relation.
  def filter_by_owner_type(relation:, scope:, filtered_repo_ids:)
    if scope == :public_scope
      relation.send(scope)
    elsif owner.is_a?(User) || owner.is_a?(Repository)
      relation.send(scope).where(["repositories.id IN (?)", filtered_repo_ids])
    else
      relation
    end
  end

  # Internal: Given a Repository scope, will return a modified scope that filters the
  # repositories according to the given type filter.
  def filter_repos_by_type(relation, type:, privacy:, affiliations:)
    return relation if type.nil? && privacy.nil?

    if type == PlatformTypes::RepositoryType::PUBLIC.downcase || privacy == PlatformTypes::RepositoryType::PUBLIC.downcase
      relation.public_scope
    elsif type == PlatformTypes::RepositoryType::PRIVATE.downcase || privacy == PlatformTypes::RepositoryType::PRIVATE.downcase
      if owner.is_a?(User) || owner.is_a?(Repository)
        # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        filtered_repo_ids = associated_repository_ids(affiliations)
        relation = relation.private_scope.where("repositories.id IN (?)", filtered_repo_ids)
        # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      end
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

  def determine_visibility(relation, privacy)
    return relation.public_scope if privacy == "public"
    return relation if permission.async_can_list_private_repos?(owner).sync

    case privacy
    when "private", "internal"
      Repository.none
    else
      relation.public_scope
    end
  end

  def fetch_repositories(owner_affiliations, scope:, order_by:, cursor:, check_large_scope:, remove_owner_in_clause:)
    if fetch_template_repositories?
      repos = owner.repository_templates_for(viewer, scope: scope)
      Platform::ArrayWrapper.new(repos)
    elsif fetch_watched_repositories?
      ids = Platform::Helpers::WatchingQuery.new(viewer, owner).fetch!.to_a

      result = ids.each_slice(Platform::Resolvers::WatchedRepositories::BATCH_SIZE).with_object(Array.new) do |repo_ids, list|
        list.concat(::Repository.where(id: repo_ids).merge(scope))
      end
      result = sort_repo_list(result, order_by)

      Platform::ArrayWrapper.new(result)
    else
      if owner.is_a?(Repository)
        owner.forks.merge(scope)
      elsif owner.is_a?(RepositoryNetwork)
        owner.repositories.merge(scope)
      elsif owner.is_a?(Topic)
        if !order_by
          # If there isn't already an order specified, we need to order using the column on
          # `repository_topics.repository_id`, otherwise this query is really expensive when
          # trying to order by `repositories.id`.
          # See https://github.com/github/communities/issues/1762.
          scope = scope.order("repository_topics.repository_id ASC")
        end

        owner.repositories.merge(scope)
      else
        repos = if remove_owner_in_clause && owner_affiliations == [:owned]
          user_associated_repository_ids = []
          scope.owned_by(owner)
        else
          user_associated_repository_ids = cache_associated_repository_ids(owner.id, owner_affiliations) do
            # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
            owner.associated_repository_ids(including: owner_affiliations)
            # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
          end

          scope.from("repositories FORCE INDEX (PRIMARY)").where(id: user_associated_repository_ids)
        end

        if GitHub.flipper[:repositories_finder_default_order].enabled?(owner)
          repos = order_by ? repos : repos.order(:id)
        end

        repos
      end
    end
  end

  def fetch_watched_repositories?
    @repo_type == REPO_TYPE_WATCHED
  end

  def fetch_template_repositories?
    @repo_type == REPO_TYPE_TEMPLATE
  end

  # Apply the specified ordering to the overall list, in case the repositories were fetched
  # in batches with only each batch being ordered in SQL
  #
  # Necessary for WatchedRepositories
  def sort_repo_list(repos, order_by)
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

  def ari_cache_key(user_id, affiliations)
    "#{user_id}:#{affiliations.join(",")}"
  end

  def cache_associated_repository_ids(user_id, affiliations)
    raise RuntimeError, "Must provide block to `cache_associated_repository_ids`" unless block_given?

    @ari_cache[ari_cache_key(user_id, affiliations)] ||= (proc do
      yield
    end).call
  end
end
