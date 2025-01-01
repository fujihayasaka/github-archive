# typed: true
# frozen_string_literal: true

module User::MemexProjectsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  include MemexProjectColumn::IDataSource

  requires_ancestor { User }

  include MemexProject::SharedMemexProjectsDependency

  included do
    T.bind(self, T.class_of(User))

    # Public: Check if this user can be added to a Memex project board.
    #
    # memex_owner - the User or Organization who owns the Memex project board
    # viewer - the currently authenticated User
    #
    # Examples:
    #
    #   # To prevent N+1s when this method is called on a list of User records, prefill it this way:
    #
    #   # Execute few queries to preload, such as in a controller action:
    #   GitHub::PrefillAssociations.prefill_batch_method(users, :can_be_added_to_memex_project?, {
    #     memex_owner: this_organization,
    #     viewer: current_user,
    #   })
    #
    #   users.each do |user|
    #     # Methods are preloaded and memoized - no queries are executed here!
    #     user.can_be_added_to_memex_project?(memex_owner: this_organization, viewer: current_user)
    #   end
    #
    # Returns a Boolean.
    batch_method :can_be_added_to_memex_project? do |*args|
      users = args.shift
      options = args.shift || {}
      memex_owner = options[:memex_owner]
      viewer = options[:viewer]

      next Hash.new(false) unless memex_owner

      blocks_by_user_id = viewer.blocking_or_blocked_by?(users)

      promises = users.map do |user|
        if user.id == viewer.id
          Promise.resolve(false) # Filter out self from suggestions
        elsif blocks_by_user_id[user.id]
          # Filter out if the target user is blocking the current user, or the current user is blocking the
          # target user
          Promise.resolve(false)
        elsif memex_owner.organization?
          memex_owner.async_member?(user).then do |is_member|
            next true if is_member
            memex_owner.user_is_outside_collaborator?(user.id)
          end
        else
          Promise.resolve(true)
        end
      end
      results = Promise.all(promises).sync

      users.zip(results).to_h
    end
  end

  # Public: Returns whether the user has projects enabled in their personal user namespace.
  #
  # Returns Boolean
  def user_projects_enabled?
    return false if is_enterprise_managed? && businesses.none?(&:user_projects_enabled?)
    true
  end

  # Checks accessibility of user owned memexes in a search scope using Authzd Batch Authorization and returns the scope that will query only accessible memexes
  # Parameters:
  #   search_scope - scope of the query that lists Memex Projects
  #   user - user viewing list of projects
  #   min_permissions_level - level of permissions we want to check for. Possible values: read, write, admin
  #   auth_method - method to use for checking permissions. Possible values: batching (enumeration api does not support user projects)
  #   filter_ids - only return the ids of the accessible projects that intersect with the filter ids
  def accessible_memexes_scope(search_scope, user, min_permission_level = "read", auth_method = :batching, filter_ids: [])
    async_accessible_memexes_scope(search_scope, user, min_permission_level, auth_method, filter_ids: filter_ids).sync
  end

  def async_accessible_memexes_scope(search_scope, user, min_permission_level = "read", auth_method = :batching, filter_ids: [])
    # Currently only batching is supported as auth_method for user projects, any other types of auth_method will be ignored
    async_accessible_memexes_scope_using_batching(search_scope, user, min_permission_level, filter_ids: filter_ids)
  end

  sig { override.returns(MemexProjectColumnValue::UserValue) }
  def memex_project_column_value
    MemexProjectColumnValue::UserValue.new(
      avatar_url: primary_avatar_url(40),
      id: id,
      display_login: display_login,
      url: permalink,
    )
  end

  # The representation of a User object for suggestions that will be sent to the
  # Memex client. Essentially this decorates the memex_project_column_value#to_hash with more
  # data.
  #
  # This will be changed to make use of MemexProjectColumnValue::UserValue
  #
  # Returns a Hash.
  def memex_suggestion_hash(selected:)
    memex_project_column_value.to_hash.merge({
      name: profile_name,
      selected: selected,
    })
  end

  # The representation of a User object as a pull request reviewer that will be
  # sent to the Memex client. Essentially this decorates the memex_project_column_value#to_hash
  # with more data.
  #
  # This will be changed to make use of MemexProjectColumnValue::UserValue
  #
  # Returns a Hash.
  def memex_reviewer_hash
    memex_project_column_value.to_hash.merge(
      name: name,
      type: self.class.to_s
    )
  end

  # Used by the GraphQL API to return all of the projects v2 that the user has read access to
  sig do
    params(
      query: Search::Queries::MemexProjectQuery,
      viewer: User,
      min_permission_level: T.any(String, Symbol),
      use_full_term_query: T::Boolean
    ).returns(
      T.nilable(MemexProject::SharedMemexProjectsDependency::MemexProjectsSearchResult)
    )
  end
  def all_projects_v2_for_user(query:, viewer:, min_permission_level: "read", use_full_term_query: false)
    accessible_memexes_ids = T.let([], T::Array[Integer])
    base_scope = prepare_scope_for_search(base_scope: MemexProject.all, viewer: viewer, query: query, use_full_term_query: use_full_term_query)

    GitHub.dogstats.time("memex.all_projects.time") do
      # Ids of projects owned by the user
      users_owned_memex_projects_ids = self.memex_projects.pluck(:id)

      # Ids of all projects to which the user has direct grant (NOT via any team).
      # This list will include ids of all user-owned projects this user was invited.
      direct_grant_memexes_ids = UserRole.where(actor_id: self.id, actor_type: "User", target_type: "MemexProject").pluck(:target_id)

      user_owned_base_scope = base_scope.where(id: users_owned_memex_projects_ids + direct_grant_memexes_ids)

      user_memexes_ids = async_accessible_memexes_scope_using_batching(
        user_owned_base_scope,
        viewer,
        min_permission_level,
        return_ids: true
      ).sync

      # Enumeration for organization owned projects.
      org_memexes_ids = accessible_memexes_scope_using_enumeration(
        base_scope,
        viewer,
        min_permission_level,
        return_ids: true,
        scoped: false
      )

      accessible_memexes_ids = user_memexes_ids + org_memexes_ids
    end

    final_scope = base_scope.where(id: accessible_memexes_ids)
    sort_and_return_search_results(
      query: query,
      scope: final_scope,
      limit: nil,
    )
  end

  # Used to limit search results to only repos with a specific milestone in the context
  # of a grouping by milestone.
  # Since the repository_ids array is not upper-bound, perform the query in batches.
  sig { params(milestone_title: String).returns(T::Array[Integer]) }
  def repo_ids_with_milestone(milestone_title)
    repository_ids = repositories.ids
    Milestone.batched_scope(:repository_id, values: repository_ids).where(title: milestone_title).pluck(:repository_id)
  end
end
