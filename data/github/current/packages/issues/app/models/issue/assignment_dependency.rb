# typed: true
# frozen_string_literal: true

module Issue::AssignmentDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Issue }

  # this is used as a fallback when we have trouble finding the repo owner's plan info
  # which can happen in some background jobs such as `RemoveNoncollabAssigneesFromIssueJob`
  DEFAULT_ASSIGNEE_LIMIT = 10

  # https://github.com/github/incident-mysql1-outages/issues/115
  #
  # Large orgs can have excessive numbers of users
  # This allows us to limit the available assignee ids reduces the number of users
  # considered to reduce timeouts at the expense of accurate results.
  PLATFORM_ASSIGNEE_LIMIT = 10_000

  # Defines how many results we want to return for type ahead assignment suggestions
  TYPE_AHEAD_PAGE_SIZE = 11

  included do
    T.bind(self, T.class_of(Issue))

    validate :assignment_length_under_limit
  end

  # Public: Set the full list of assignees for this issue. For
  # backwards-compatibility, sets the assignee_id field to the first assignee.
  #
  # new_assignees - The Array of Users that will replace the existing list of
  #                 assignees. WARNING: This should include ALL assignees you
  #                 wish to add or keep.
  #
  # Returns an Array of Users
  def assignees=(new_assignees)
    previous_assignees = assignees.reload
    new_assignees = new_assignees.compact.uniq

    assignees_changed = (previous_assignees.sort_by(&:id) != new_assignees.sort_by(&:id))

    # These are the new assignees that were also previously assigned
    assignees_to_keep = new_assignees & previous_assignees

    # This code checks that the new assignees are valid
    # It assumes that previously saved assignees are valid
    unassignable_users = (new_assignees - assignees_to_keep).select do |user|
      available_assignee_ids.exclude?(user.id)
    end

    if unassignable_users.present?
      # Remove invalid assignees - they shouldn't be autosaved
      errors.add :assignees, "unable to be set"
      new_assignees = new_assignees - unassignable_users
    end

    new_assignees = if single_assignee?
      # when only one assignee is allowed, we want an array with the sole assignee
      if new_assignees.size > 1
        # track whenever we are truncating assignees on single assignee issue/PRs
        # (this is expected to happen when single assignee selection isn't implemented in whatever client app the user is using)
        stats_subject = pull_request ? "pull_request" : "issue"
        GitHub.dogstats.increment("assignees_truncated", tags: ["subject:#{stats_subject}"])
      end

      # Take the first new assignee if it's single assignee and discard any existing assignees
      only_new_assignees = new_assignees - assignees_to_keep
      if only_new_assignees.size > 0
        only_new_assignees.take(1)
      else # If there weren't any new assignees, take the first existing assignee
        assignees_to_keep.take(1)
      end
    else
      # Don't allow more than X assignees
      new_assignees.first(assignee_limit)
    end

    removed_assignments = []
    # We're removing any record which exists already that we're not adding or keeping
    unless new_record?
      new_assignments = assignments.for_assignees(new_assignees)
      removed_assignments = (removed_assignments + T.unsafe(self.assignments).excluding_ids(new_assignments.to_a)).uniq
      removed_assignments = removed_assignments.reject do |unassigned|
        users_being_destroyed.find { |id| unassigned.assignee_id == id }
      end
    end

    super(new_assignees)

    removed_assignments.each(&:trigger_unassigned_event)

    # Keep the legacy assignee_id field synced with the assignees.
    self[:assignee_id] = new_assignees.first && new_assignees.first.id

    # Nuke the memoization in assigned_to?
    remove_instance_variable(:@_assigned_to) if instance_variable_defined?(:@_assigned_to)

    remove_instance_variable(:@users_being_destroyed) if instance_variable_defined?(:@users_being_destroyed)

    if assignees_changed
      self.dirty = true
    end

    new_assignees
  end

  # Public: Return the assignee limit from the repo's plan configuration
  #
  # Returns an integer
  def assignee_limit
    @assignee_limit ||= repository&.plan_limit(:issue_pr_assignees) || DEFAULT_ASSIGNEE_LIMIT
  end

  # Public: Are we only allowing users to select one assignee?
  #
  # Returns a Boolean
  def single_assignee?
    assignee_limit == 1
  end

  # Public: Set the assignee for this Issue. CAUTION: This method will clear
  # any other assignments on this issue.
  #
  # new_assignee - The User to set as the new assignee
  #
  # Returns the new_assignee User
  def assignee=(new_assignee)
    self.assignees = [new_assignee].compact
    super
  end

  # Public: Add the specified assignees.
  #
  # users - Array of Users to add as assignees.
  #
  # Returns self (the Issue)
  def add_assignees(*users)
    self.assignees = self.assignees.reload + users.flatten.uniq
    self
  end

  # Public: Remove the specified assignees.
  #
  # users - Array of Users to remove as assignees.
  #
  # Returns self (the Issue)
  def remove_assignees(*users)
    users = users.flatten.uniq
    users.each do |user|
      self.users_being_destroyed << user.id if user.being_destroyed?
    end
    self.assignees = self.assignees.reload - users
    self
  end

  # Public: Is this issue assigned to that user?
  #
  # possible_assignee - a User
  #
  # Returns a Boolean
  def assigned_to?(possible_assignee)
    return false unless possible_assignee

    @_assigned_to ||= Hash.new do |hash, key|
      hash[key] = assignees.include?(key) || assignee == key
    end
    @_assigned_to[possible_assignee]
  end

  # Public: Can this issue be assigned to that user?
  #
  # This is a permissions check, not a check against existing assignees. This
  # means the result will be true for already-assigned users.
  #
  # possible_assignee - a User
  #
  # Returns a Boolean.
  def assignable_to?(possible_assignee, after_save = false)
    return false unless possible_assignee
    available_assignee_ids(after_save).include?(possible_assignee.id)
  end

  # Public: Get the IDs of the users that can be assigned to this issue.
  #
  # This is a permissions check, not a check against existing assignees. This
  # means the result will include users that are already assigned.
  #
  # Returns an array of Integers.
  def available_assignee_ids(after_save = false, limit: nil)
    return @available_assignee_ids unless @available_assignee_ids.nil?

    # user ids for all commenters
    commenter_ids = comments.pluck(:user_id)

    # user ids for everyone with write access to the repo
    # this actually also loads the users, not just their ids - WOMP
    privileged_ids = Instrumentation.track_time("assignees.fetch_privileged_ids.dist.time") { user_ids_with_privileged_access.compact }

    # add 'em together and remove any abusive users
    potential_assignees = if GitHub.flipper[:available_assignee_ids_with_repo_read_access].enabled?(self.repository)
      (commenter_ids + privileged_ids + user_ids_with_repo_read_access).uniq
    else
      (commenter_ids + privileged_ids).uniq
    end

    # https://github.com/github/incident-mysql1-outages/issues/115
    #
    # potential_assignees can be very large, if passed the limit arbitrarily limits
    # the number of user_ids to return to avoid query timeouts.
    potential_assignees = potential_assignees.take(limit) if limit.present?

    if self.repository&.copilot_swe_agent_enabled?
      swe_agent_app = Apps::Privileged.integration(:copilot_swe_agent)
      potential_assignees.unshift(swe_agent_app.bot.id).uniq! unless swe_agent_app.nil?
    end

    suspended_ids = Instrumentation.track_time("assignees.fetch_suspended_ids.dist.time") { suspended_and_blocking_user_ids(potential_assignees, after_save) }
    @available_assignee_ids = potential_assignees - suspended_ids
  end

  def visible_available_assignee_ids_for(viewer, after_save = false, limit: nil)
    repository = T.must(self.repository)
    assignee_ids = available_assignee_ids(after_save, limit: limit)

    # The viewer has full access to see the assignable users, including private org members
    # Private and internal repositories should have full access, also.
    return assignee_ids if !repository.public? || repository.member?(viewer) || !T.unsafe(repository.owner).organization? || T.unsafe(repository.owner).member?(viewer)

    # If we are at this point it means the viewer is a non-member (or logged out), and viewing a public repository.
    # Therefore we should consider users which have commented and public members.
    commenter_ids = comments.pluck(:user_id)
    public_members_ids = T.unsafe(repository.owner).public_members.where(id: assignee_ids).pluck(:id)
    potential_assignees = (commenter_ids + public_members_ids).uniq
    potential_assignees = potential_assignees.take(limit) if limit.present?
    suspended_ids = Instrumentation.track_time("assignees.fetch_suspended_ids.dist.time") { suspended_and_blocking_user_ids(potential_assignees, after_save) }

    potential_assignees - suspended_ids
  end

  # Internal: Find the users that are blocking the modfiyng_user, and suspended users
  # Those users are considered unavailable for assignment
  #
  # Check saved status -- if the record has already been saved with the assignment,
  # we want to ensure that the assignment was added by a non-blocked user.
  #
  # Returns an array of user_ids
  def suspended_and_blocking_user_ids(privileged_ids, after_save = false)
    return [] if privileged_ids.empty?

    unavailable_blocking_user_ids = Instrumentation.track_time("assignees.unavailable_blocking_user_ids.dist.time") { unavailable_blocking_user_ids(privileged_ids, after_save) }
    unavailable_blocking_user_ids + User.where(id: privileged_ids).suspended.pluck(:id)
  end

  # Internal: Find the users that cannot be assigned by the modifying user
  # due to blocked status
  #
  # If the record has already been saved, we want to allow a blocking user
  # to remain assigned, as long as the blocked user isn't the one doing the assigning.
  #
  # Returns an array of user_ids
  def unavailable_blocking_user_ids(assignee_ids, after_save = false)
    assignee_ids = user_ids_assigned_by_modifying_user(assignee_ids) if after_save
    assignee_ids & IgnoredUser.where(ignored_id: modifying_user.id).pluck(:user_id)
  end

  # Internal: Find the users that were previously assigned by the modifying user
  #
  # Returns an array of user_ids
  def user_ids_assigned_by_modifying_user(assignee_ids)
    self.events.assigns
      .where(issue_events: { actor: modifying_user })
      .where(issue_event_details: { subject_id: assignee_ids })
      .pluck(:subject_id)
  end

  def visible_available_assignees_for(viewer)
    User.where(id: visible_available_assignee_ids_for(viewer)).includes(:profile)
  end

  # Internal: Remove all non-collaborator assignees. Sometimes people are
  # assigned who shouldn't be (e.g. after being removed from a team). This
  # makes sure we cover our tracks.
  #
  # Returns the new list of assignees if any noncollab assignees are detected
  def remove_noncollab_assignees
    if has_noncollab_assignee?
      # reset @available_assignee_ids so they can be recalculated
      @available_assignee_ids = nil
      self.skip_noncollab_assignee_callback = true
      self.assignees = self.assignees - self.noncollab_assignees(true)
      self.save
    end
  end

  # Internal: Is this issue assigned to anyone?
  #
  # Returns a boolean.
  def assigned?
    ActiveRecord::Base.connected_to(role: :reading) do
      !!assignee_id ||
        assignments.exists? ||
        assignees.present?
    end
  end

  # Internal: Is this issue assigned to any users who are not collaborators on
  # the repo?
  #
  # Returns a boolean.
  def has_noncollab_assignee?
    noncollab_assignee? || noncollab_assignees(true).any?
  end

  # Internal: Gets all associated assignments that are for users who are not
  # collaborators on the repo.
  #
  # Returns an Array of Users
  def noncollab_assignees(after_save = false)
    self.assignees.select do |member|
      noncollab_assignee?(member, after_save)
    end
  end

  # Resort assignees list prioritizing the current user and current assignee
  # followed by an alpha sort.
  #
  # users - Array of possible assignee Users
  #
  # Returns Array of Users.
  def sorted_assignees_list(current_user:)
    @sorted_assignees_list ||= {}
    @sorted_assignees_list[current_user] ||= begin
      list = self.assignees + non_assigned_potential_assignees(current_user: current_user)

      if current_user && user = list.delete(current_user)
        list.unshift user
      end

      list.uniq
    end
  end

  def filtered_assignees_list(current_user, search_query)
    timer = Timer.start
    sanitized_query = ActiveRecord::Base.sanitize_sql_like(search_query)
    users = User.preload(:profile, :user_status)
      .left_joins(:profile)
      .where(id: visible_available_assignee_ids_for(current_user))
      .where.not(type: "Bot")
      .merge(User.where("login LIKE ?", "%#{sanitized_query}%").or(Profile.where("name LIKE ?", "%#{sanitized_query}%")))
      .filter_spam_for(current_user)
      .references(:profile)

    # Sort by login & profile name, taking priority to those whom start with the search query.
    users = users.to_a.sort_by do |u|
      [
        u.login.start_with?(search_query) ? "0" : "1",
        u.safe_profile_name.start_with?(search_query) ? "0" : "1",
        u.login,
        u.safe_profile_name
      ]
    end

    timer.stop
    GitHub.dogstats.distribution("assignees.dist.fetch_filtered_users", timer.elapsed_ms, tags: [])

    users.take(TYPE_AHEAD_PAGE_SIZE)
  end

  # Private: Get the list of users that have not been assigned to this issue.
  #
  # This performs a permission check and also checks against existing assignees.
  # This means the result will not include already assigned users.
  #
  #
  # Returns an array of Users.
  private def non_assigned_potential_assignees(current_user:)
    @non_assigned_potential_assignees ||= begin

      available_ids = Instrumentation.track_time("assignees.get_available_assignees_ids.dist.time") do
        visible_available_assignee_ids_for(current_user)
      end
      Instrumentation.track_time("assignees.fetch_users.dist.time") do
        User.includes(:profile, :user_status)
          .where(id: available_ids - self.assignees.pluck(:id))
          .where.not(type: "Bot")
          .filter_spam_for(current_user)
          .order(:login)
      end
    end
  end

  # Internal: Is this a collaborator on the repo?
  #
  # member - Any User (defaults to the Issue's assignee to preserve existing
  #          previous method behavior)
  #
  # Returns a boolean.
  def noncollab_assignee?(member = T.unsafe(self).assignee, after_save = false)
    assigned_to?(member) && !assignable_to?(member, after_save)
  end

  # Internal: Create an assignment event for a new assignee.
  #
  # assigned - The User who was assigned
  #
  # Returns nothing
  def trigger_assigned_event(assigned)
    return unless assigned

    ignore_duplicate_records do
      # Yes, this is wrong. actor and subject should be swapped. But this has been wrong since day one and
      # it's virtually impossible to fix. So we're just hiding it the upper layers (API, Hydro).
      events.create(event: "assigned", actor_id: assigned.id, subject: modifying_user, assignee: assigned)
    end
  end

  # Internal: Create an unassignment event when an assignee is removed.
  #
  # unassigned - The User who was unassigned
  #
  # Returns nothing
  def trigger_unassigned_event(unassigned)
    return unless unassigned

    if GitHub.context[:hide_staff_user] && GitHub.guard_audit_log_staff_actor?
      subject = User.staff_user
    else
      subject = modifying_user
    end
    ignore_duplicate_records do
      # Yes, this is wrong. actor and subject should be swapped. But this has been wrong since day one and
      # it's virtually impossible to fix. So we're just hiding it the upper layers (API, Hydro).
      events.create(event: "unassigned", actor_id: unassigned.id, subject: subject, assignee: unassigned)
    end
  end

  # DEPRECATED: create an "unassigned" event if the issue was just assigned to
  # somebody else.
  def create_unassigned_event
    return unless assignee_id_was

    removed_assignee = User.find_by id: assignee_id_was
    trigger_unassigned_event(removed_assignee)
  end

  # Internal: Keeps track of the users being destroyed. We won't call
  # `trigger_unassigned_event` to avoid a possible race condition.
  #
  # Returns an array.
  def users_being_destroyed
    @users_being_destroyed ||= []
  end

  private def assignment_length_under_limit
    return unless repository = self.repository

    # issues with multiple assigness can be moved to plans
    # that support different limits. In that case we only run this validation
    # if the assignees are being changed.
    if assignees.any?(&:changed?) && assignments.length > assignee_limit
      errors.add(:assignees, "You may not add more than #{assignee_limit} assignee(s)")
    end
  end
end
