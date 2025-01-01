# typed: true
# frozen_string_literal: true

module Team::Nested
  extend T::Helpers
  extend ActiveSupport::Concern
  requires_ancestor { Team }

  include GitHub::BatchMethod

  class_methods do

    # Public: Get user members on any of the specified teams.
    #
    # team_ids: The teams IDs to search in
    # immediate_only: A boolean indicating whether to search in descendants as well
    #
    # Returns a User scope
    def members_of(*team_ids, immediate_only: true)
      User.where(id: member_ids_of(team_ids, immediate_only: immediate_only))
    end

    # Public: Get user ids of members on any of the specified teams.
    #
    # team_ids: The teams IDs to search in
    # immediate_only: A boolean indicating whether to search in descendants as well
    #
    # Returns a list of user ids
    def member_ids_of(*team_ids, immediate_only: true, with_business_teams: false)
      team_ids = team_ids.flatten.compact
      if immediate_only
        if with_business_teams
          Team.batch_user_ids_for_with_business_teams(team_ids)
        else
          Team.user_ids_for(team_ids)
        end
      else
        descendant_or_self_member_ids_for(team_ids, with_business_teams: with_business_teams)
      end
    end

    # Public: Determine whether a user is a member of any of a group of teams
    #
    # team_ids: The teams IDs to search in
    # user: The user to determine membership for
    # immediate_only: A boolean indicating whether to search in descendants as well
    #
    # Returns a boolean indicating membership
    def member_of?(*team_ids, user_id, immediate_only: true)
      member_ids_of(team_ids, immediate_only: immediate_only).include?(user_id)
    end

    # Public: Find descendant teams for a given set of teams and returns their IDs.
    #
    # teams           - An Array of Teams to look for descendants.
    # immediate_only  - (Optional) A Boolean determining if only immediate descendants
    #                   will be looked up.
    #
    # Returns an Array.
    def descendant_ids(teams, immediate_only: false)
      async_descendant_ids(teams, immediate_only: immediate_only).sync
    end

    def async_descendant_ids(teams, immediate_only: false)
      promise = Platform::Loaders::TeamDescendants.load_all \
        teams,
        immediate_only: immediate_only

      promise.then do |descendant_ids_by_parent|
        descendant_ids_by_parent.values.flatten
      end
    end

    def descendant_or_self_memberships_indexed_by_member_id(team_ids, with_business_teams: false)
      subject_type = with_business_teams ? %w(BusinessTeam Team) : "Team"
      Ability.where(subject_id: team_ids, subject_type:, actor_type: "User")
        .where("priority <= ?", Ability.priorities[:direct]).distinct.pluck(:subject_id, :actor_id)
        .each_with_object({}) do |(team_id, actor_id), hash|
          hash[actor_id] ||= []
          hash[actor_id] << team_id
        end
    end

    private

    # Private: Return a scope of all users on all teams in team_ids
    #
    # team_ids: The team_ids to search in
    #
    # Return a User scope
    def descendant_or_self_members_for(team_ids)
      return User.none unless team_ids.any?

      User.where(id: descendant_or_self_member_ids_for(team_ids))
    end

    def descendant_or_self_member_ids_for(team_ids, with_business_teams: false)
      subject_type = with_business_teams ? %w(BusinessTeam Team) : "Team"
      Ability.where(subject_id: team_ids, subject_type: subject_type, actor_type: "User").
        where("priority <= ?", Ability.priorities[:direct]).distinct.pluck(:actor_id)
    end

    def descendant_or_self_member_ids_for_indexed_by_team_ids(team_ids)
      Ability.where(subject_id: team_ids, subject_type: "Team", actor_type: "User").
        where("priority <= ?", Ability.priorities[:direct]).distinct.pluck(:subject_id, :actor_id).
        each_with_object({}) do |(team_id, actor_id), hash|
          hash[team_id] ||= []
          hash[team_id] << actor_id
        end
    end
  end

  included do
    batch_method(:parent_team) do |teams|
      parent_teams = T.let(T.unsafe(self), T.class_of(Team)).where(id: teams.map(&:parent_team_id)).index_by(&:id)
      teams.index_with { |team| parent_teams[team.parent_team_id] }
    end
  end

  class TeamTreeNode < Arvore::Node
    self.node_model = Team
  end

  attr_reader  :parent_team_id, :parent_team_id_was
  attr_reader  :enqueue_handle_team_parent_changes_after_commit

  def parent_team_id=(id)
    @parent_team_was = @parent_team
    @parent_team_id_was = @parent_team_id

    clear_preloaded_batch_method_value(:parent_team)
    @parent_team_id = id
  end

  def parent_team=(team)
    @parent_team_was = @parent_team
    @parent_team_id_was = @parent_team_id

    self.parent_team_id = team.try(:id)
    unsafe_preload_batch_method_value(:parent_team, team)
    save
  end

  def parent_team_was
    @parent_team_was ||= active_record_class.where(id: parent_team_id_was).first
  end

  def tree_node
    if tree_path.blank?
      raise ArgumentError, <<~MSG
              Can't create a tree node without a tree path.
              You are probably trying to call a tree related method in a callback
              before the tree_path gets populated.
            MSG
    end
    TeamTreeNode.new(tree_path)
  end

  def reset_parent_team
    @parent_team_id =
      if has_attribute?(:tree_path) && tree_path
        tree_node.parent_id
      else
        nil
      end
    clear_preloaded_batch_method_value(:parent_team)
  end

  def update_tree_path
    tree_node = if tree_path.nil?
      insert_tree_node
    else
      move_tree_node
    end

    self.tree_path = tree_node.path
  end

  def insert_tree_node
    tree_node = TeamTreeNode.create(id, parent_team_id.presence)

    if parent_team_id.present?
      instrument :change_parent_team,
        parent_team: parent_team&.to_s,
        parent_team_id: parent_team_id,
        parent_team_id_was: nil,
        parent_team_was: nil
    end

    tree_node
  end

  # Moves the team to the given parent
  #
  # Raises Team::ParentChange::CannotAcquireLockError (an StandardError) if
  # another team is being moved.
  #
  # Returns the new TeamTreeNode after the team was moved.
  #
  # Note that the recalculation of abilities will be enqueued to happen in the background.
  # So moving a tree node, should be as fast as updating the records down in the hierarchy
  # to reflect their new paths (see Arvore::Node#move_to)
  #
  def move_tree_node
    old_node = tree_node
    @parent_team_id_was ||= old_node.parent_id
    return old_node if parent_team_id_was == parent_team_id

    lock = Team::ParentChange::Lock.new(org_id: self.organization_id)
    locked_successfully = lock.try_lock!

    old_path = old_node.path
    old_descendants = old_node.descendants
    new_node = old_node.move_to(parent_team_id.presence)

    enqueue_after_team_changes_commited(old_path, new_node.path, old_descendants)

    # this is needed to push the audit-log event
    instrument :change_parent_team,
      parent_team: parent_team&.to_s,
      parent_team_id: parent_team_id,
      parent_team_id_was: parent_team_id_was,
      parent_team_was: parent_team_was&.to_s

    new_node
  rescue Team::ParentChange::CannotAcquireLockError => err
    locked_successfully = false
    raise err
  ensure
    lock.unlock if lock.present? && locked_successfully
  end

  def enqueue_after_team_changes_commited(old_path, new_path, old_descendants)
    payload = Team::ParentChange::Payload.new(team_id: self.id, old_path: old_path, new_path: new_path, old_descendants: old_descendants)
    pending = Team::ParentChange::PendingQueue.new(org_id: organization_id)
    pending.enqueue(payload)
    @enqueue_handle_team_parent_changes_after_commit = true
  end

  # Public: Returns the ids of teams which parent is this one.
  #
  # Returns [id]
  def child_team_ids
    tree_node.immediate_children
  end

  # Public: Determine if this team has any child teams
  #
  # Returns a boolean indicating whether this team has any child teams
  def has_child_teams?
    child_team_ids.present?
  end

  def child_teams
    team_ids = child_team_ids
    return active_record_class.none if team_ids.empty?
    active_record_class.where(id: team_ids, deleted: false)
  end

  # Public: Returns an array with the team's id and ancestor team ids
  #
  # Returns [id]
  def id_and_ancestor_ids
    [self.id] + self.ancestor_ids
  end

  # Overrides Subject#ancestor_ids
  def ancestor_ids
    tree_node.ancestors
  end

  # Overrides Subject#ancestors
  #
  # Returns an ActiveRecord::Relation of Teams, sorted by seniority.
  def ancestors
    team_ids = ancestor_ids
    return active_record_class.none if team_ids.empty?
    active_record_class.where(id: team_ids, deleted: false).order(:tree_path)
  end

  # Overrides Subject#ancestors?
  def ancestors?
    ancestor_ids.present?
  end

  # Public: Returns a list of ids of descendant teams.
  #
  # Returns an Array.
  def descendant_ids(immediate_only: false)
    async_descendant_ids(immediate_only: immediate_only).sync
  end

  def async_descendant_ids(immediate_only:)
    async_organization.then do |_organization|
      Platform::Loaders::TeamDescendants.load(self, immediate_only: immediate_only)
    end
  end

  # Public: Returns an active record relation for the team's descendant teams.
  #
  # Returns a Team AR Relation.
  def descendants(immediate_only: false)
    async_descendants(immediate_only: immediate_only).sync
  end

  def async_descendants(immediate_only:)
    async_descendant_ids(immediate_only: immediate_only).then do |descendant_ids|
      next active_record_class.none if descendant_ids.empty?
      active_record_class.where(id: descendant_ids, deleted: false)
    end
  end

  def ancestor_and_descendant_ids
    ancestor_ids | descendant_ids
  end

  # Public: Returns an array containing this team descendants in depth first order
  #
  def descendants_depth_first
    descendants.sort { |team| team.tree_node.depth }
  end

  # Public: Returns true if the team has descendant teams. False if it does not.
  #
  # Returns a Boolean.
  def descendants?
    descendant_ids.present?
  end

  def root?
    tree_node.root == id
  end

  def descendant_or_self_members(action: nil)
    return direct_members_for(descendant_ids + [id], action) if action && action != :read

    User.where(id: descendant_or_self_member_ids(action: action))
  end

  def descendant_or_self_member_ids(action: nil)
    return direct_member_ids_for(descendant_ids + [id], action) if action && action != :read

    descendant_or_self_members_scope.pluck(:actor_id)
  end

  def descendant_or_self_members_count(action: nil)
    return direct_members_for_count(descendant_ids + [id], action) if action && action != :read

    descendant_or_self_members_scope.count(:actor_id)
  end

  def descendant_members(action: nil)
    direct_members_for(descendant_ids, action)
  end

  def descendant_member_ids(action: nil)
    direct_member_ids_for(descendant_ids, action)
  end

  def descendant_members_count(action: nil)
    direct_members_for_count(descendant_ids, action)
  end

  # Public: Returns descendant teams that the user is a member of. Includes direct aand indrect teams.
  #
  # EX. Engineering -> AppEngineering -> Identity -> PizzaPenguin
  #     if a user is a direct member of Identity they are also an indirect member of AppEngineering
  #
  #     engineering.descendants_where_user_is_a_member(user)
  #     # => [AppEngineering, Identity]
  #
  # user - user to use for membership check
  #
  # Returns an Team AR Relation.
  def descendants_where_user_is_a_member(user, immediate_only: false)
    team_ids =
      ActiveRecord::Base.connected_to(role: :reading) do
        unfiltered_team_ids = descendant_ids(immediate_only: immediate_only)

        return active_record_class.none unless unfiltered_team_ids.present?

        Ability.where(actor_id: user.id, actor_type: "User", subject_id: unfiltered_team_ids, subject_type: "Team",
          priority: [Ability.priorities[:direct], Ability.priorities[:indirect]]).distinct.pluck(:subject_id)
      end

    active_record_class.where(id: team_ids, deleted: false)
  end

  # Public: Returns descendant teams that have no members. Includes direct and indirect teams.
  #
  # EX. Engineering -> AppEngineering -> Identity -> PizzaPenguin
  #     if a user is a direct member of Identity they are also an indirect member of AppEngineering
  #
  #     engineering.descendants_without_members
  #     # => [PizzaPenguin]
  #
  # Returns an Team AR Relation.
  def descendants_without_members(immediate_only: false)
    active_record_class.without_members(descendant_ids(immediate_only: immediate_only))
  end

  # Public: Computes users that ignore a Team's notification.
  #
  # Returns array of user IDs or empty array
  def unnotifiable_member_ids
    GitHub.newsies.user_ids_ignoring_list(self).select do |user_id|
      user = User.new(id: user_id)
      FeatureFlag.vexi.enabled_or_raise?(:ignorable_team_notifications, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end
  end

  # Public: Computes user IDs of team members that should be notified.
  #         When the feature flag is enabled, this will omit any members ignoring the team in newsies.
  #
  # Returns array of user IDs or empty array
  def notifiable_member_ids
    if FeatureFlag.vexi.enabled_or_raise?(:ignorable_team_notifications, self.organization) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      descendant_or_self_member_ids - unnotifiable_member_ids
    else
      descendant_or_self_member_ids
    end
  end

  # Public: Computes users that should be notified.
  #
  # Returns an ActiveRecord::Relation of Users
  def notifiable_members
    User.where(id: notifiable_member_ids)
  end

  def active_record_class
    T.unsafe(self.class)
  end

  def descendant_or_self_members_scope
    Ability.where(subject_id: ability_id, subject_type: ability_type, actor_type: "User")
      .where("priority <= ?", Ability.priorities[:direct]).distinct
  end

  # Internal
  #
  # Return a User AR scope for the direct members of the given
  # team_ids. The cabability of those members will match
  # the given action (:read, :write, :admin)
  #
  def direct_members_for(team_ids, action)
    User.where(id: direct_member_ids_for(team_ids, action))
  end

  def direct_member_ids_for(team_ids, action)
    direct_members_scope(team_ids, action).pluck(:actor_id)
  end

  def direct_members_for_count(team_ids, action)
    direct_members_scope(team_ids, action).count(:actor_id)
  end

  def direct_members_scope(team_ids, action)
    scope = Ability.where(
      subject_id: team_ids,
      subject_type: ability_type,
      actor_type: "User",
      priority: Ability.priorities[:direct]
    )

    if action.present?
      scope = scope.where(action: Ability.actions[action])
    end

    scope.distinct
  end
end
